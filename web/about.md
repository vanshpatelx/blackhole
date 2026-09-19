# About Black Hole

Black Hole is a free, open-source Mac app that keeps the things you need during a working day — your tasks, a focus timer, a daily notepad and today's calendar — in the one place your eyes already go: the notch at the top of the screen. Hover it and the workspace drops out. Move away and it disappears. Nothing sits in a window you have to find, and nothing competes for space in the Dock.

## Why it exists

Most task apps ask you to go somewhere to use them. That trip is small, but you make it dozens of times a day, and each one is a chance to get distracted by something else. Putting the day one hover away removes the trip entirely. The focus timer works the same way: while it runs, the notch becomes a live island showing progress on one side and time remaining on the other, so you can see where you are without opening anything.

## How it is built

Black Hole is a native macOS app written in Swift and SwiftUI, with no Electron and no web view. Everything you create is stored locally in `~/Library/Application Support/Black Hole/` using SwiftData. Calendar events are read through EventKit, which is why iCloud, Google and Outlook accounts all work without Black Hole ever asking for a password — they are the accounts macOS already has. Events are read-only; the app never creates, edits or deletes anything in your calendar.

## Open source

The whole app is MIT licensed and developed in the open at [github.com/vanshpatelx/blackhole](https://github.com/vanshpatelx/blackhole). Every change lands through a pull request with continuous integration running lint and tests. Releases are built by GitHub Actions from a tag, so the DMG you download is built from the source you can read. If something is wrong, the issue tracker is the fastest way to reach us.

## AI access

Black Hole ships a Model Context Protocol server, so Claude, ChatGPT, Cursor and Claude Code can work with your day: adding tasks, starting focus sessions, reading back what you spent your week on. It runs on your own Mac and answers only while the app is open. Your task data never passes through a server of ours.

---

[Home](https://getblackhole.app/) · [About](https://getblackhole.app/about) · [Contact](https://getblackhole.app/contact) · [Privacy](https://getblackhole.app/privacy) · [llms.txt](https://getblackhole.app/llms.txt)
