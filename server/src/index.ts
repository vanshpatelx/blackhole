/**
 * Black Hole enrollment API.
 *
 * Hands each install a permanent address like https://a7f3.mcp.getblackhole.app and the
 * Cloudflare Tunnel token needed to serve it from the user's Mac.
 *
 * Requests and task data never touch this Worker: it only creates the tunnel and the DNS record.
 * Traffic flows from the assistant to Cloudflare's edge and down the user's own tunnel.
 */

interface Env {
  INSTALLS: KVNamespace;
  /** Only secret needed: a token with Account → Cloudflare Tunnel → Edit and Zone → DNS → Edit. */
  CF_API_TOKEN: string;
  ZONE_NAME: string;
  CF_ACCOUNT_ID?: string;
  CF_ZONE_ID?: string;
  HOSTNAME_SUFFIX: string;
  HOSTNAME_PREFIX: string;
  LOCAL_PORT: string;
}

interface Install {
  tunnelId: string;
  hostname: string;
  slug: string;
  createdAt: string;
}

const CF_API = "https://api.cloudflare.com/client/v4";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

async function cf<T>(env: Env, path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${CF_API}${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.CF_API_TOKEN}`,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  const payload = (await response.json()) as { success: boolean; result: T; errors?: unknown };
  if (!response.ok || !payload.success) {
    throw new Error(`Cloudflare API ${path} failed: ${JSON.stringify(payload.errors ?? payload)}`);
  }
  return payload.result;
}

/** Account and zone ids are looked up once from the token, so deploying needs a single secret. */
async function ids(env: Env): Promise<{ accountId: string; zoneId: string }> {
  if (env.CF_ACCOUNT_ID && env.CF_ZONE_ID) {
    return { accountId: env.CF_ACCOUNT_ID, zoneId: env.CF_ZONE_ID };
  }
  const cached = (await env.INSTALLS.get("cf:ids", "json")) as { accountId: string; zoneId: string } | null;
  if (cached) return cached;

  const zones = await cf<Array<{ id: string; account: { id: string } }>>(env, `/zones?name=${env.ZONE_NAME}`);
  const zone = zones[0];
  if (!zone) throw new Error(`Zone ${env.ZONE_NAME} not found for this API token`);

  const resolved = { accountId: zone.account.id, zoneId: zone.id };
  await env.INSTALLS.put("cf:ids", JSON.stringify(resolved), { expirationTtl: 86_400 });
  return resolved;
}

/** Short, readable, unguessable: 8 hex characters is plenty inside a secret-token URL. */
function newSlug(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(4));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes));
}

/** Rough per-IP limit so one machine can't create tunnels in a loop. */
async function rateLimited(env: Env, request: Request): Promise<boolean> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const key = `rl:${ip}:${new Date().toISOString().slice(0, 13)}`;
  const count = Number((await env.INSTALLS.get(key)) ?? "0");
  if (count >= 10) return true;
  await env.INSTALLS.put(key, String(count + 1), { expirationTtl: 3600 });
  return false;
}

async function enroll(request: Request, env: Env): Promise<Response> {
  const { accountId, zoneId } = await ids(env);
  const { installId } = (await request.json()) as { installId?: string };
  if (!installId || !/^[a-fA-F0-9-]{20,64}$/.test(installId)) {
    return json({ error: "installId must be a UUID" }, 400);
  }
  if (await rateLimited(env, request)) return json({ error: "Too many enrollments, try later" }, 429);

  // Re-enrolling the same install returns a fresh token for the tunnel it already owns.
  const existing = (await env.INSTALLS.get(`install:${installId}`, "json")) as Install | null;
  const slug = existing?.slug ?? newSlug();
  const hostname = existing?.hostname ?? `${env.HOSTNAME_PREFIX}${slug}.${env.HOSTNAME_SUFFIX}`;

  let tunnelId = existing?.tunnelId;
  let token: string;

  if (tunnelId) {
    token = await cf<string>(env, `/accounts/${accountId}/cfd_tunnel/${tunnelId}/token`);
  } else {
    const tunnel = await cf<{ id: string; token: string }>(env, `/accounts/${accountId}/cfd_tunnel`, {
      method: "POST",
      body: JSON.stringify({ name: `bh-${slug}`, tunnel_secret: randomSecret(), config_src: "cloudflare" }),
    });
    tunnelId = tunnel.id;
    token = tunnel.token;

    await cf(env, `/accounts/${accountId}/cfd_tunnel/${tunnelId}/configurations`, {
      method: "PUT",
      body: JSON.stringify({
        config: {
          ingress: [
            { hostname, service: `http://127.0.0.1:${env.LOCAL_PORT}` },
            { service: "http_status:404" },
          ],
        },
      }),
    });

    await cf(env, `/zones/${zoneId}/dns_records`, {
      method: "POST",
      body: JSON.stringify({
        type: "CNAME",
        name: hostname,
        content: `${tunnelId}.cfargotunnel.com`,
        proxied: true,
        comment: `Black Hole install ${installId}`,
      }),
    });

    const record: Install = { tunnelId, hostname, slug, createdAt: new Date().toISOString() };
    await env.INSTALLS.put(`install:${installId}`, JSON.stringify(record));
  }

  return json({ hostname, tunnelToken: token, url: `https://${hostname}` });
}

async function revoke(request: Request, env: Env): Promise<Response> {
  const { accountId, zoneId } = await ids(env);
  const { installId } = (await request.json()) as { installId?: string };
  if (!installId) return json({ error: "installId required" }, 400);

  const existing = (await env.INSTALLS.get(`install:${installId}`, "json")) as Install | null;
  if (!existing) return json({ ok: true });

  const records = await cf<Array<{ id: string }>>(env, `/zones/${zoneId}/dns_records?name=${existing.hostname}`);
  for (const record of records) {
    await cf(env, `/zones/${zoneId}/dns_records/${record.id}`, { method: "DELETE" });
  }
  await cf(env, `/accounts/${accountId}/cfd_tunnel/${existing.tunnelId}`, { method: "DELETE" });
  await env.INSTALLS.delete(`install:${installId}`);
  return json({ ok: true });
}

/** Reports which permissions the configured API token actually has, to make setup mistakes obvious. */
async function diagnose(env: Env): Promise<Response> {
  const { accountId, zoneId } = await ids(env);
  let lastError = "";
  const check = async (path: string) => {
    try {
      await cf(env, path);
      return true;
    } catch (error) {
      lastError = String(error).slice(0, 200);
      return false;
    }
  };
  // A short hash of the token, so you can confirm the Worker holds the same one you tested locally.
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(env.CF_API_TOKEN ?? ""));
  const fingerprint = [...new Uint8Array(digest)].slice(0, 4).map((b) => b.toString(16).padStart(2, "0")).join("");

  const tunnels = await check(`/accounts/${accountId}/cfd_tunnel?per_page=1`);
  const dns = await check(`/zones/${zoneId}/dns_records?per_page=1`);
  return json({
    tokenFingerprint: fingerprint,
    lastError,
    tokenCanManageTunnels: tunnels,
    tokenCanManageDNS: dns,
    ready: tunnels && dns,
    needs: [
      tunnels ? null : "Account → Cloudflare Tunnel → Edit",
      dns ? null : "Zone → DNS → Edit (getblackhole.app)",
    ].filter(Boolean),
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "POST" && url.pathname === "/v1/enroll") return await enroll(request, env);
      if (request.method === "POST" && url.pathname === "/v1/revoke") return await revoke(request, env);
      if (url.pathname === "/health") return json({ ok: true });
      if (url.pathname === "/v1/diagnose") return await diagnose(env);
      return json({ error: "Not found" }, 404);
    } catch (error) {
      return json({ error: String(error) }, 502);
    }
  },
};
