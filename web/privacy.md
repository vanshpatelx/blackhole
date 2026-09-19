# Privacy

Black Hole has no accounts, no analytics and no telemetry. Nobody, including us, can see what you put in it.

## What is stored, and where

Your tasks, focus sessions and notes live in a database on your own Mac, at `~/Library/Application Support/Black Hole/`. Nothing is uploaded anywhere. There is no sync service, no cloud backup and no sign-in. If you delete the app and that folder, the data is gone — so if you want a copy, Settings has an export that writes everything out as JSON you can read.

## Calendar

Calendar access is optional, and read-only. Black Hole asks macOS for today's events through EventKit, which means your iCloud, Google and Outlook accounts stay where they already are, and the app never handles your credentials. It never creates, edits or deletes an event. You choose which calendars appear in Settings, and you can revoke access at any time in System Settings → Privacy & Security → Calendars.

## Spotify

If you use the playback card, Black Hole talks to the copy of Spotify running on your Mac through Apple events — the same mechanism the menu bar uses. It reads the current track and sends play, pause, next and previous. No Spotify account or API key is involved, and nothing about your listening leaves your machine.

## AI access

AI access is off until you turn it on. When you do, your Mac gets a permanent HTTPS address and runs a tunnel so an assistant can reach the MCP server on your machine. Requests travel from the assistant, through Cloudflare, straight down that tunnel to your Mac. Your tasks and notes are not stored by, or visible to, any server of ours.

One thing to know: the access token is part of that URL, so it is visible to whoever operates the edge the request crosses — for the built-in address, the getblackhole.app Cloudflare zone — and to whichever assistant you paste it into. Treat the URL like a password, and reset it from the Copy menu if it leaks. If you would rather the traffic never left your own network, installing Tailscale switches the tunnel to your private tailnet instead.

## This website

getblackhole.app is static files on Cloudflare. It sets no cookies and runs no analytics. The page asks GitHub for the latest release number so the download button points at the current version; that request goes to GitHub, not to us.

---

[Home](https://getblackhole.app/) · [About](https://getblackhole.app/about) · [Contact](https://getblackhole.app/contact) · [Privacy](https://getblackhole.app/privacy) · [llms.txt](https://getblackhole.app/llms.txt)
