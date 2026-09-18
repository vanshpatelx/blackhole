# Black Hole enrollment API

A Cloudflare Worker that gives each Black Hole install a permanent address, for example
`https://mcp-a7f3.getblackhole.app`, so cloud assistants (claude.ai, ChatGPT) can reach the app.

**Your tasks never pass through this Worker.** It only creates a Cloudflare Tunnel and a DNS record.
Requests then flow from the assistant to Cloudflare's edge and down the tunnel the app runs on your Mac.

## Endpoints

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/v1/enroll` | `{ "installId": "<uuid>" }` | `{ hostname, tunnelToken, url }` |
| POST | `/v1/revoke` | `{ "installId": "<uuid>" }` | `{ ok: true }` |
| GET | `/health` | | `{ ok: true }` |

Enrolling twice with the same `installId` keeps the hostname and returns a fresh tunnel token.

## Deploy

```bash
cd server
npm install -g wrangler        # or npx wrangler
wrangler login                 # or set CLOUDFLARE_API_TOKEN

wrangler kv namespace create INSTALLS   # put the id into wrangler.toml
wrangler secret put CF_API_TOKEN        # Account: Cloudflare Tunnel:Edit, Zone: DNS:Edit
wrangler deploy
```

The API token needs **Account → Cloudflare Tunnel → Edit** and **Zone → DNS → Edit** on `getblackhole.app`.
Account and zone ids are discovered from the token and cached in KV, so that's the only secret.

## Why hostnames are one level deep

Cloudflare's free Universal SSL covers `*.getblackhole.app` but not `*.mcp.getblackhole.app`, so a
two-level name would have no certificate. Addresses are therefore `mcp-<slug>.getblackhole.app`.

## Abuse control

Enrollment is rate limited to 10 per IP per hour. Tunnels are cheap but not free of admin, so
prune unused ones with `/v1/revoke` (the app calls it when a user turns hosted access off).
