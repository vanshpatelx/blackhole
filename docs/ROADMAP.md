# Roadmap

## v0.1: first public release ✅
- Notch workspace: tasks, focus timer, daily notepad, events
- Insights for the last 7 days
- Floating button that opens the workspace on any display
- Events from iCloud, Google, Outlook and other calendars on the Mac, with a per-calendar picker
- Holey the mascot, with moods
- JSON export, launch at login, demo mode

## v0.2: Black Hole for AI assistants (MCP server) ✅
- Built-in MCP server so Claude, Cursor and other MCP clients can list, add and complete tasks, start focus sessions, read notes and pull insights
- One MCP URL to paste into any client, private over Tailscale or public through a tunnel
- See [SYNC_AND_MCP.md](SYNC_AND_MCP.md)

## v0.3: multi-device sync, bring your own backend
- Sync foundation: change tracking, soft deletes, last-write-wins conflict handling
- Supabase provider (hosted or self-hosted): paste a URL and key, sign in, done
- SQL migrations and a step-by-step setup guide

## v0.4: more ways to sync
- Live updates between devices (realtime)
- Tiny self-hostable Black Hole Sync server (Docker, SQLite or Postgres)
- iCloud sync for signed builds

## Later
- Import tasks from other MCP servers and tools (GitHub Issues, Linear, Notion)
- Direct Google Calendar sign-in, for people who don't want to add their account to macOS
- On-device AI: turn notes into tasks, daily summaries
- Custom reminder and time-limit pickers, recurring tasks
- Rebindable hotkey, themes, localization
- Notarized builds with automatic updates (Sparkle)
- Intel and universal builds
