<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Black Hole app icon">
</p>

<h1 align="center">Black Hole</h1>

<p align="center">
  <b>Your whole day, one hover away.</b><br>
  Tasks, a focus timer, a daily notepad and today's calendar, living in your Mac's notch.
</p>

<p align="center">
  <a href="https://github.com/vanshpatelx/blackhole/releases/latest"><b>Download for Mac</b></a> ·
  <a href="https://getblackhole.app">getblackhole.app</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a>
</p>

<p align="center">
  <img src="docs/images/workspace.png" alt="Black Hole workspace dropping out of the MacBook notch">
</p>

## Why

Your to-do app is in another window, your timer is in another app, and your notes are somewhere else. Black Hole puts all of it at the top of your screen. Hover the notch (or press <kbd>⌥</kbd><kbd>N</kbd>), do the thing, and get back to work.

It's free, open source, and your data never leaves your Mac.

## Features

- **Today's tasks**: add, check off, drag to reorder, set time limits and reminders, move to tomorrow. Unfinished tasks roll over to the next day on their own.
- **Focus timer**: countdown or stopwatch with pause, resume and +5 minutes. While it runs, the notch becomes a live island: a progress ring on one side and the countdown on the other. It pauses when your Mac sleeps.
- **Daily notepad**: saves as you type. Put the cursor on a line and press <kbd>⌘</kbd><kbd>↩</kbd> to turn it into a task.
- **Events from all your calendars**: iCloud, Google (as many accounts as you like), Outlook/Exchange and subscribed calendars, color-coded and read-only. Pick which calendars show in **Settings → Calendars**.
- **Insights**: focus time, completed vs. planned tasks, active days and your streak over the last week.
- **Floating button**: a draggable button for any display (great with external monitors). Click it and the whole workspace opens right next to it.
- **Works with AI assistants (MCP)**: turn on the built-in MCP server and Claude, Cursor or any MCP client can list and add tasks, run focus sessions, read your notes and pull insights.
- **Holey the mascot**: blinks, looks up when you hover, cheers when you finish something, gets serious during focus sessions, and dozes off when you've been away.

<p align="center">
  <img src="docs/images/floating.png" width="49%" alt="Workspace opened from the floating button">
  <img src="docs/images/insights.png" width="49%" alt="Insights with weekly focus time">
</p>

<p align="center">
  <img src="docs/images/moods.png" width="80%" alt="Holey's moods: normal, happy, focused, sleepy">
</p>

## Install

1. Download the latest `BlackHole-x.y.z.dmg` from [Releases](https://github.com/vanshpatelx/blackhole/releases/latest).
2. Open it and drag **Black Hole** into **Applications**.
3. Open Black Hole. Current builds aren't notarized by Apple yet, so macOS will block the first launch:
   - Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Black Hole, **or**
   - run `xattr -dr com.apple.quarantine "/Applications/Black Hole.app"` in Terminal.

**Requirements:** macOS 14 Sonoma or later on Apple silicon. No notch? It still works: the workspace opens from the top center of your screen, or from the floating button. Intel Macs can [build from source](#build-from-source) after changing `ARCHS` in `project.yml`.

## How to use

| Action | How |
|---|---|
| Open the workspace | Hover the notch, press <kbd>⌥</kbd><kbd>N</kbd>, or click the floating button |
| Close it | <kbd>Esc</kbd>, click outside, or move the pointer away |
| Note line → task | <kbd>⌘</kbd><kbd>↩</kbd> in the notepad |
| Task actions | Right-click a task, or use its **⋯** menu |
| Move the floating button | Drag it; it snaps to the nearest screen edge. Right-click it for more |
| Full window | **Open app** in the top bar |

## Google and Outlook calendars

Black Hole reads calendars through macOS, so add your accounts there once:

1. **System Settings → Internet Accounts → Add Account → Google** (repeat for each Google account; Microsoft Exchange/Outlook works the same way).
2. Make sure **Calendars** is switched on for the account.
3. In Black Hole, open **Settings → Calendars** and tick the calendars you want to see.

## Use it from Claude, Cursor and other AI apps (MCP)

Black Hole has a built-in [Model Context Protocol](https://modelcontextprotocol.io) server. It's off by default and only listens on `127.0.0.1`, protected by a token.

1. Open **Settings → AI Assistants** and turn on **MCP server**.
2. Click **Copy setup for…** and pick your client:
   - **Claude Code**: paste the copied `claude mcp add …` command into your terminal.
   - **Cursor**: paste the JSON into `~/.cursor/mcp.json`.
   - **Claude Desktop**: paste the JSON into `~/Library/Application Support/Claude/claude_desktop_config.json`. It uses the bundled `blackhole-mcp` command, which launches Black Hole if it isn't running.
3. Ask things like *"add my three most urgent GitHub issues to today"*, *"start a 45-minute focus session on the launch post"* or *"what did I focus on this week?"*

### Your own machines and agents (Tailscale network)

If you use [Tailscale](https://tailscale.com), other machines on your tailnet, including servers running your own agents, can reach Black Hole directly. Nothing is exposed to the internet and the address never changes.

1. In **Settings → AI Assistants**, turn on **Tailscale network**.
2. Click **Copy tailnet URL**: `http://100.x.y.z:52321/mcp/<token>`.
3. Use it as the MCP URL on your other machine.

### claude.ai, ChatGPT and other web apps (remote access)

Cloud-hosted assistants run on their own servers and can't reach `127.0.0.1`. Turn on **Remote access** in **Settings → AI Assistants**, click **Copy connector URL**, then paste it into **claude.ai → Settings → Connectors → Add custom connector** (no authentication) or a ChatGPT connector (developer mode, no authentication).

Two ways to get that public URL:

| | **Tailscale Funnel** (default when Tailscale is installed) | **Cloudflare quick tunnel** |
|---|---|---|
| Setup | Tailscale signed in, Funnel enabled for your tailnet | `brew install cloudflared` |
| URL | `https://your-mac.your-tailnet.ts.net/mcp/<token>`, **permanent** | `https://random-words.trycloudflare.com/mcp/<token>`, **changes on every restart** |
| Good for | Connectors you set up once | Networks that can't reach `ts.net`, or no Tailscale |

Switch between them from the small provider button under the Remote access switch.

Good to know:
- The URL contains your secret token, so **anyone with it can use your planner**. Treat it like a password; **Reset Access Token** in the **Copy setup for…** menu revokes it immediately.
- Public access only works while Black Hole is open and Remote access is on. Quick tunnel URLs die when the app restarts, so prefer Tailscale for anything you configure once.
- The current URLs are also written to `~/Library/Application Support/Black Hole/mcp.json`, handy for scripts and agents.

| Tool | What it does |
|---|---|
| `list_tasks`, `add_task`, `update_task`, `delete_task` | Manage tasks for any day |
| `start_focus`, `pause_focus`, `resume_focus`, `stop_focus`, `focus_status` | Control the focus timer |
| `read_note`, `append_note` | Read and add to the daily notepad (never overwrites) |
| `get_insights` | Planned/completed tasks and focus minutes per day, plus streak |
| `todays_events` | Today's events from the calendars you chose to show |

## Privacy

Everything is stored locally in `~/Library/Application Support/Black Hole/`. There are no accounts, analytics or outgoing network calls. The optional MCP server only accepts connections from this Mac, unless you turn on **Remote access**, which opens a token-protected Cloudflare tunnel until you turn it off. Calendar access is optional and read-only: Black Hole never creates, edits or deletes events. You can export everything as JSON from **Settings → Data**.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/vanshpatelx/blackhole.git
cd blackhole
make run      # generate the Xcode project, build and launch
```

| Command | What it does |
|---|---|
| `make project` | Generate `BlackHole.xcodeproj` from `project.yml` (then open it in Xcode if you like) |
| `make run` | Debug build and launch |
| `make demo` | Launch with sample data in memory; your real data is untouched |
| `make test` | Run the unit tests |
| `make dmg` | Build a Release DMG into `dist/` |

Needs Xcode 16 or later. The Xcode project is generated and not committed, so edit `project.yml` for target settings.

### Project layout

```
BlackHole/
├─ App/              App entry, shared services (database, timer, calendar, mascot mood)
├─ Notch/            Notch panel window, hover + hotkey handling, notch shape, top bar
├─ FloatingButton/   Draggable floating button and the workspace that opens beside it
├─ MCP/              Local MCP server (JSON-RPC over HTTP on 127.0.0.1) and its tools
├─ Features/         Tasks, Focus timer, Notepad, Events, Insights, Settings, Dashboard
├─ Data/             SwiftData models, JSON export, demo data
├─ DesignSystem/     Colors, cards, buttons, dot-matrix digits, Holey the mascot
└─ Resources/        App icon
BlackHoleMCP/        `blackhole-mcp` stdio bridge bundled inside the app
```

## Roadmap

Next up: **multi-device sync** you control (your own Supabase or self-hosted server). See [docs/ROADMAP.md](docs/ROADMAP.md) and the [sync + MCP design](docs/SYNC_AND_MCP.md).

## Contributing

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
