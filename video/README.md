# Launch film

A 24-second launch film for Black Hole, built with [Remotion](https://www.remotion.dev), with an
original soundtrack synthesized from scratch.

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
| `4x5` | Phones |

## How it's built

**Cut to the music.** The soundtrack is 138 BPM, so a beat is exactly 13 frames and a bar is 52.
Tempo and the section layout live in `src/film/timing.json`, which both the film and the
soundtrack generator read, so pictures and music cannot drift apart.

**Faster or slower is a one-line change.** Each section has a bar count and a `speed`. Raising a
section's speed plays its animations faster without re-timing any of them, and its sound cues move
with it. Changing `beat` re-times the whole film and re-arranges the music to match.

**The soundtrack is generated, not licensed.** `scripts/audio.mjs` composes and synthesizes the
music and every sound effect — plucked strings, pads, drums, a riser into the drop — with no
samples and nothing borrowed, so the film can be posted anywhere. Running it is deterministic, so
the WAVs aren't checked in; every render script regenerates them first.

**The UI is rebuilt, not recorded.** The panel, island and command bar are React components using
the colours from `BlackHole/DesignSystem/DesignSystem.swift`, so they stay sharp at any size. They
sit on a drawn 14-inch MacBook screen at true proportions, and a camera pushes in so the UI fills
the frame once it's established.

**What keeps it from looking generated:** a warm paper ground instead of a dark gradient; type
that arrives word by word, holding its place so lines never reflow; one serif word per line at
most; a pointer that moves along a curve, overshoots and settles; hard cuts on the beat; film grain.

## The beats

| Bars | Section |
|---|---|
| 1–2 | "You have a to-do list. / You never *look* at it." |
| 3 | The screen, a hand heading for the notch: "So we put it *here*." |
| 4–5 | The drop: the workspace opens out of the notch; a task ticked, the timer started |
| 6 | Close on the island: "The notch keeps *time*." |
| 7–8 | ⌥ Space, and a sentence becoming a task |
| 9–10 | An assistant adding three tasks over MCP |
| 11–12 | A cut on every beat: meetings, music, insights, repeats, notes, any screen, Holey |
| 13–14 | Black Hole — *Your whole day, one hover away.* |

## Licence

Remotion is free for individuals and companies of up to three people; larger companies need a
[company licence](https://www.remotion.dev/license). Inter and Instrument Serif are under the SIL
Open Font License.
