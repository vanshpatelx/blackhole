# Black Hole — your whole day, one hover away

A free, open-source Mac app that keeps tasks, a focus timer, a daily notepad and today's calendar
in your Mac's notch. Everything is stored locally. There are no accounts and no tracking.

- **Download:** https://github.com/vanshpatelx/blackhole/releases/latest/download/BlackHole.dmg
- **Source:** https://github.com/vanshpatelx/blackhole
- **Licence:** MIT
- **Requires:** macOS 14 or later, Apple silicon

## What it does

- **Today's tasks** — add, check off, drag to reorder, set time limits and reminders. Unfinished
  work rolls over to tomorrow on its own.
- **Focus timer** — countdown or stopwatch. While it runs the notch becomes a live island: progress
  on one side, time left on the other. It pauses when the Mac sleeps.
- **Daily notepad** — saves as you type. Put the cursor on a line, press Cmd-Return, and it becomes
  a task for today.
- **Events** — iCloud, Google (any number of accounts) and Outlook, colour-coded and read-only.
  Five minutes before a meeting the notch counts down to it; clicking joins the call.
- **Spotify** — what's playing, with previous, play/pause and next.
- **Insights** — focus time, completed against planned tasks, active days and streak.
- **Anywhere** — no notch, or an external display? The workspace opens at the top of the screen, or
  beside a floating button you can drag wherever you like.

## For AI assistants

Black Hole ships an MCP (Model Context Protocol) server so Claude, ChatGPT, Cursor and Claude Code
can run someone's day. Turning on AI access gives that Mac a permanent HTTPS address; pasting it
into an assistant is the whole setup.

Thirteen tools are exposed:

| Tool | What it does |
|---|---|
| `list_tasks`, `add_task`, `update_task`, `delete_task` | Manage tasks for any day |
| `start_focus`, `pause_focus`, `resume_focus`, `stop_focus`, `focus_status` | Control the focus timer |
| `read_note`, `append_note` | Read and add to the daily notepad |
| `get_insights` | Planned and completed tasks, focus minutes per day, streak |
| `todays_events` | Today's events, with join links |

The server runs on the user's own Mac and answers only while Black Hole is open. Task data never
passes through any server of ours. See https://github.com/vanshpatelx/blackhole#ai-access.

## Pages

- [About](https://getblackhole.app/about)
- [Contact](https://getblackhole.app/contact)
- [Privacy](https://getblackhole.app/privacy)
- [llms.txt](https://getblackhole.app/llms.txt)
