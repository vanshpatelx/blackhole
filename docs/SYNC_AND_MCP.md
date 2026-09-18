# Sync and MCP design

Status: **proposal**, open for feedback in GitHub issues.

Black Hole is local-first and free. This document covers two opt-in extensions:

1. **MCP**: let AI assistants (Claude, Cursor, anything that speaks the Model Context Protocol) read and manage your day.
2. **Sync**: keep tasks, notes and focus history in step across several Macs, on infrastructure *you* choose.

Neither changes the default. With nothing configured, everything stays on your Mac exactly as it does today.

---

## Principles

- **Local database stays the source of truth.** The UI always reads and writes the local SwiftData store. Sync and MCP work alongside it, never in between, so the app is instant and works offline.
- **Bring your own backend.** No Black Hole servers, no accounts with us. You point the app at a backend you control.
- **No database passwords on laptops.** We deliberately don't accept a raw Postgres connection string (see [Why not a raw database URL?](#why-not-a-raw-database-url)).
- **Small, boring protocol.** Sync is plain "push my changes, pull yours since cursor X", so it's easy to implement new backends.

---

## Part 1: MCP (planned for v0.2)

### 1A. Black Hole as an MCP server (build first)

Black Hole runs a local MCP server. Any MCP client on the Mac can then work with your day:

> "Claude, look at my open GitHub issues and add the three most urgent ones to today in Black Hole."
> "What did I spend my focus time on this week?"
> "Start a 45-minute focus session on the launch tweet."

**Tools**

| Tool | What it does |
|---|---|
| `list_tasks(day?)` | Tasks for a day (default today) with status, time limit and reminder |
| `add_task(title, day?, time_limit_minutes?, remind_at?)` | Create a task |
| `update_task(id, title?, done?, day?)` | Rename, complete, or move a task |
| `delete_task(id)` | Remove a task |
| `start_focus(task_id?, minutes?)`, `pause_focus()`, `stop_focus()` | Control the timer |
| `focus_status()` | Current session, time left |
| `read_note(day?)`, `append_note(text, day?)` | Daily notepad |
| `insights(days = 7)` | Focus minutes, completed/planned, streak |
| `todays_events()` | Calendar events (only if the user connected Calendar) |

**Resources:** `blackhole://today` is a one-shot summary of today's tasks, focus and events, handy as context.

**How it runs**

- **Shipped in v0.2.** The running app hosts the server on `127.0.0.1` over MCP **Streamable HTTP** (plain JSON responses, no SSE), protected by a random token. Going through the app, not the database file, means changes show up in the notch instantly and there are no two-writers problems.
- The app bundle also ships a tiny `blackhole-mcp` command (stdio) for clients that only support stdio. It forwards to the local HTTP endpoint and can launch the app if it isn't running.
- Implemented directly (it's small JSON-RPC) rather than with the [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk), to keep the app dependency-free.
- **Settings → Integrations → MCP**: an on/off switch (off by default), "Copy config for Claude Desktop / Cursor / Claude Code", and "Regenerate token".
- Planned: mark writes made through MCP in the UI (a small ✦ on the task) so you can see what an assistant changed.

### Remote access for cloud assistants (v0.2.1)

claude.ai and ChatGPT connectors call MCP from their own servers and can't reach `127.0.0.1`, and they generally can't send custom headers. **Remote access** covers both:
- Black Hole runs the user's `cloudflared` as a quick tunnel (`cloudflared tunnel --url http://127.0.0.1:<port>`), shows the `trycloudflare.com` URL, and restarts it if it drops.
- Connectors authenticate with the token in the path: `https://<tunnel>/mcp/<token>`. The local endpoint keeps the `Authorization: Bearer` header.
- Tunnel requests (identified by Cloudflare's `CF-Connecting-IP`) are refused whenever Remote access is off. The process is stopped on quit, and a stray one from a crash is cleaned up on the next launch.
- **Tailscale support (v0.2.1):** when Tailscale is installed, Funnel is the default provider because its URL is permanent, and a second listener on the tailnet address lets the user's own machines and agents connect privately with no public exposure. Cloudflare quick tunnels remain the fallback for networks that can't reach `ts.net`.
- Current URLs are mirrored into `mcp.json` so scripts and agents can discover them.
- Later: OAuth for connectors, per-tool permissions for remote callers (for example read-only), and stable URLs through a named tunnel on the user's own domain.

### 1B. MCP task sources (later)

Black Hole as an MCP **client**: connect other MCP servers (GitHub, Linear, Notion, Jira) and pull their items into an **Inbox** you can drag into today. Mapping arbitrary tools to tasks is fragile, so this ships per source with an explicit mapping (which tool, which fields), starting with GitHub Issues.

---

## Part 2: Multi-device sync (planned for v0.3+)

### Data model changes (foundation)

Every synced record (`TaskItem`, `FocusSession`, `DailyNote`) gains:

| Field | Purpose |
|---|---|
| `id: UUID` | Already present; globally unique, so no ID clashes across devices |
| `updatedAt: Date` | Set on every change; drives last-write-wins |
| `deletedAt: Date?` | Soft delete ("tombstone") so deletions sync |
| `deviceID: String` | Which Mac last wrote it, for debugging and loop prevention |

Plus a local `SyncState` (last pull cursor and last push time per provider).

**Conflicts:** last write wins per record, compared by `updatedAt`. For tasks and focus sessions that's simple and predictable. Notes are one document per day; v1 is last write wins, and a later version can merge line by line.

**The running timer** syncs as a normal `FocusSession` record, so a paused session can be resumed on another Mac. Live timer mirroring comes with realtime.

### The sync engine

```swift
protocol SyncProvider {
    /// Upload local changes made since the last successful push.
    func push(_ changes: ChangeSet) async throws
    /// Download remote changes since `cursor`; returns the new cursor.
    func pull(since cursor: SyncCursor?) async throws -> (ChangeSet, SyncCursor)
    /// Optional: notify when remote data changes so we can pull right away.
    func subscribe(_ onChange: @escaping () -> Void) async throws
}
```

`SyncEngine` runs push, then pull, on launch, on wake, a few seconds after local edits (debounced), on a remote change notification, and every few minutes as a fallback. Failures back off and show a small status line in Settings. Nothing blocks the UI.

### Provider 1: Supabase (recommended first)

Why: free tier, works hosted or self-hosted, real per-user auth, row-level security, and realtime built in. Official [Swift SDK](https://github.com/supabase/supabase-swift).

User flow:
1. Create a Supabase project (or use a self-hosted one).
2. Run our SQL migration (`supabase/migrations/0001_blackhole.sql`), which creates `tasks`, `focus_sessions` and `notes` with `user_id` columns and row-level security policies.
3. In **Settings → Sync**, paste the **Project URL** and **anon key**, then sign in with an email magic link or Sign in with Apple.
4. Do the same on your other Macs. Done.

The anon key is designed to be public; security comes from sign-in plus row-level security, so every user only ever sees their own rows. Realtime subscriptions make other devices update within about a second.

### Provider 2: Black Hole Sync server (self-host)

For people who don't want Supabase: a small open-source server (single binary or `docker run`) with SQLite or Postgres, implementing the same push/pull API over HTTPS plus a WebSocket for change notifications. Settings takes a **server URL + access token**.

### Provider 3: iCloud

The zero-setup option for regular users, via CloudKit. It needs Black Hole's official Apple Developer signing, so it only works in official signed builds; builds from source use providers 1 or 2.

### Why not a raw database URL?

Pasting `postgres://user:password@host/db` into the app sounds simplest, but:
- Every Mac would hold full database credentials. One lost laptop exposes everything, and there's no per-user permission layer.
- Many networks block direct database ports; hosted Postgres often requires extra SSL setup.
- There's no push notification of changes, so no realtime.
- Schema changes would break older app versions talking to the database directly.

Supabase's URL + anon key gives the same "paste two values and go" experience without those problems. We may still add a direct Postgres mode later as an explicitly labelled power-user option.

---

## Calendars

Calendar events are **not** synced by Black Hole: each Mac reads its own macOS calendar database, which already syncs iCloud, Google and Exchange accounts. The "which calendars are visible" choice is a per-Mac setting.

A direct Google Calendar connection (OAuth, `calendar.readonly`) is on the roadmap for people who don't want Google in macOS Internet Accounts. It needs a verified Google Cloud OAuth app, so it comes after the core sync work.

## Local AI (exploration)

Separately from sync: optional on-device intelligence using Apple's on-device model (macOS 26+) or a local Ollama model. Ideas include "turn my notepad into tasks", "summarize my week", and "suggest a time limit". It's opt-in, and nothing leaves the Mac.

---

## Rollout

| Version | Scope |
|---|---|
| v0.2 | MCP server (1A), Settings → Integrations |
| v0.3 | Sync foundation (fields, engine, tombstones) + Supabase provider + setup guide |
| v0.4 | Realtime, self-host sync server, iCloud for signed builds |
| later | MCP task sources (1B), local AI |

## Open questions

- Should MCP writes need confirmation (a notification with Allow/Deny) by default, or only for deletes?
- Sign in with Apple needs Apple Developer setup; is email magic link enough to start?
- Do we sync Settings (card colors, hotkey) too, or only data?
