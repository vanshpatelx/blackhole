/**
 * Serves the site, and answers agents in Markdown when they ask for it.
 *
 * Browsers send `Accept: text/html,...` and get the page. Agents that send `Accept: text/markdown`
 * get the same content as Markdown, which is cheaper for them to read than parsing HTML. Both
 * answers carry `Vary: Accept` so caches keep them apart.
 *
 * It also counts visits, privately: no cookies, nothing in the browser, no IP addresses stored.
 * See `record` below and the Privacy page for exactly what's kept.
 */

const PAGES = new Set(["/", "/about", "/contact", "/privacy"]);
const OWN_HOSTS = new Set(["getblackhole.app", "www.getblackhole.app"]);
const DMG = "https://github.com/vanshpatelx/blackhole/releases/latest/download/BlackHole.dmg";
// Link previews, crawlers, monitors and scripts. They are not people, so they aren't counted as visits.
const AUTOMATED = /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|quora|pinterest|whatsapp|telegram|curl|wget|python|httpclient|axios|node-fetch|go-http|java\/|okhttp|headless|lighthouse|monitor|uptime|scan/i;

/** "/about.html", "/about/" and "/about" are one page. */
const pageOf = (pathname) => pathname.replace(/\.html$/, "").replace(/\/+$/, "") || "/";

let todaysSalt = { day: "", salt: "" };

/**
 * Today's random salt. It exists for one day: the daily cleanup deletes yesterday's, after which
 * nobody — including whoever runs this site — can work an old visitor code back to anything.
 */
async function saltFor(env, day) {
  if (todaysSalt.day === day) return todaysSalt.salt;
  const fresh = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
  await env.DB.prepare("INSERT OR IGNORE INTO salts (day, salt) VALUES (?, ?)").bind(day, fresh).run();
  const row = await env.DB.prepare("SELECT salt FROM salts WHERE day = ?").bind(day).first();
  todaysSalt = { day, salt: row.salt };
  return row.salt;
}

/**
 * Counts one request. Kept: when, which page, what kind (a view, a download click, or an agent
 * reading the Markdown), the linking site's domain, the country Cloudflare reports, and a visitor
 * code — a hash of IP and browser name under today's salt, so a person's views on the same day
 * count once. The IP itself is never written anywhere.
 */
async function record(env, request, kind, path) {
  if (!env.DB) return;
  const now = new Date();
  const day = now.toISOString().slice(0, 10);
  const salt = await saltFor(env, day);
  const ip = request.headers.get("cf-connecting-ip") || "";
  const ua = request.headers.get("user-agent") || "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}|${ip}|${ua}`));
  const visitor = [...new Uint8Array(digest)].slice(0, 8).map((b) => b.toString(16).padStart(2, "0")).join("");
  let referrer = null;
  try {
    const host = new URL(request.headers.get("referer") || "").hostname;
    if (host && !OWN_HOSTS.has(host)) referrer = host;
  } catch {}
  await env.DB.prepare("INSERT INTO hits (ts, day, kind, path, visitor, referrer, country) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .bind(Math.floor(now.getTime() / 1000), day, kind, path, visitor, referrer, request.cf?.country ?? null)
    .run();
}

/** Counting happens after the response is on its way, and a failure never touches the page. */
function count(ctx, env, request, kind, path) {
  // Our own checks (web/verify.sh) mark themselves, so testing the site never inflates its numbers.
  if (request.headers.get("x-blackhole-check")) return;
  const purpose = request.headers.get("sec-purpose") || request.headers.get("purpose") || "";
  if (/prefetch|prerender/i.test(purpose)) return;
  if (kind !== "agent" && AUTOMATED.test(request.headers.get("user-agent") || "")) return;
  ctx.waitUntil(record(env, request, kind, path).catch(() => {}));
}

/** Markdown twin for a path, or null when there isn't one. */
function markdownPath(pathname) {
  const clean = pathname.replace(/\/+$/, "") || "/";
  if (clean === "/") return "/index.md";
  if (/\.[a-z0-9]+$/i.test(clean)) return null;
  return `${clean}.md`;
}

function wantsMarkdown(request) {
  // Browsers never name text/markdown; agents that want it say so explicitly.
  return /text\/markdown/i.test(request.headers.get("accept") || "");
}

function markdown(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/markdown; charset=utf-8",
      vary: "Accept",
      "cache-control": "public, max-age=300"
    }
  });
}

const NOT_FOUND_MD = `# 404 — page not found

That page doesn't exist on getblackhole.app.

Black Hole is a free, open-source Mac app that keeps tasks, a focus timer, notes and today's
calendar in the notch, and exposes them to AI assistants over MCP.

Where to go instead:

- [Home](https://getblackhole.app/) — what the app does
- [llms.txt](https://getblackhole.app/llms.txt) — how an agent should use this project
- [Sitemap](https://getblackhole.app/sitemap.xml) — every page on this site
- [Source and docs](https://github.com/vanshpatelx/blackhole) — README, MCP tool list, releases
`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Download buttons point here, so a click can be counted before handing off to GitHub.
    if (url.pathname === "/download") {
      if (request.method === "GET") count(ctx, env, request, "download", "/download");
      return new Response(null, { status: 302, headers: { location: DMG, "cache-control": "no-store" } });
    }

    // A small, honest description of how this project's MCP server works.
    if (url.pathname === "/.well-known/mcp") {
      const manifest = await env.ASSETS.fetch(new Request(`${url.origin}/well-known-mcp.json`, request));
      if (manifest.ok) {
        return new Response(manifest.body, {
          headers: { "content-type": "application/json; charset=utf-8", vary: "Accept" }
        });
      }
    }

    if (wantsMarkdown(request)) {
      const path = markdownPath(url.pathname);
      if (path) {
        const asset = await env.ASSETS.fetch(new Request(`${url.origin}${path}`, request));
        if (asset.ok) {
          if (request.method === "GET") count(ctx, env, request, "agent", pageOf(url.pathname));
          return markdown(await asset.text());
        }
      }
      return markdown(NOT_FOUND_MD, 404);
    }

    const response = await env.ASSETS.fetch(request);
    if (response.status === 404) {
      const page = await env.ASSETS.fetch(new Request(`${url.origin}/404.html`, request));
      if (page.ok) {
        return new Response(page.body, {
          status: 404,
          headers: { "content-type": "text/html; charset=utf-8", vary: "Accept" }
        });
      }
    }

    const page = pageOf(url.pathname);
    if (request.method === "GET" && response.status === 200 && PAGES.has(page)) count(ctx, env, request, "view", page);

    // Agents and caches need to know this URL answers differently depending on Accept.
    const out = new Response(response.body, response);
    out.headers.set("vary", "Accept");
    return out;
  },

  /** Daily: drop yesterday's salt, and anything older than a year. */
  async scheduled(event, env) {
    if (!env.DB) return;
    const today = new Date().toISOString().slice(0, 10);
    const yearAgo = Math.floor(Date.now() / 1000) - 365 * 24 * 3600;
    await env.DB.batch([
      env.DB.prepare("DELETE FROM salts WHERE day < ?").bind(today),
      env.DB.prepare("DELETE FROM hits WHERE ts < ?").bind(yearAgo)
    ]);
  }
};
