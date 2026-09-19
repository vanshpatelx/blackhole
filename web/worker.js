/**
 * Serves the site, and answers agents in Markdown when they ask for it.
 *
 * Browsers send `Accept: text/html,...` and get the page. Agents that send `Accept: text/markdown`
 * get the same content as Markdown, which is cheaper for them to read than parsing HTML. Both
 * answers carry `Vary: Accept` so caches keep them apart.
 */

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
  async fetch(request, env) {
    const url = new URL(request.url);

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
        if (asset.ok) return markdown(await asset.text());
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

    // Agents and caches need to know this URL answers differently depending on Accept.
    const out = new Response(response.body, response);
    out.headers.set("vary", "Accept");
    return out;
  }
};
