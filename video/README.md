# Launch video

A 31-second launch film for Black Hole, built with [Remotion](https://www.remotion.dev) — the app's
UI is rebuilt as React components rather than screen-recorded, so it stays sharp at any size and
matches the real colours exactly (taken from `BlackHole/DesignSystem/DesignSystem.swift`).

```bash
cd video
npm install
npm run studio        # preview and scrub in the browser
npm run render:all    # writes out/blackhole-launch-{16x9,1x1,4x5}.mp4
```

| File | For |
|---|---|
| `16x9` | X, YouTube, the website |
| `1x1` | LinkedIn and X feeds |
| `4x5` | Phones, where it takes the most of the screen |

## The beats

1. **Hook** — the problem, in the first two seconds, because that's all autoplay gives you
2. **Notch** — where your day could live instead
3. **Open** — the workspace drops out of the notch
4. **Tick** — the actual job: ticking something off
5. **Island** — focus starts and the notch becomes the timer (time-lapsed so the ring visibly moves)
6. **Command bar** — ⌥Space, typing a sentence, the date lifted out of it
7. **Assistant** — the same job, done by Claude or ChatGPT over MCP
8. **End** — what it is, and where to get it

It is silent on purpose: X and LinkedIn autoplay muted, so the captions carry the story. Add a
licensed music track before posting if you want one.

## Licence

Remotion is free for individuals and companies of up to three people; larger companies need a
[company licence](https://www.remotion.dev/license).
