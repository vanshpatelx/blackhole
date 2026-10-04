// The final mix: music, voiceover, sound effects and room tone, placed on the film's beat grid,
// processed, and mastered to -14 LUFS (what X, LinkedIn and YouTube normalise towards).
//
//   node scripts/mix.mjs   →   public/audio/mix.wav   (run audio.mjs and voice.mjs first)
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { SR, biquad, buf, compress, db, place, readWavAt, reseed, rmsDb, room, writeWav } from "./lib/dsp.mjs";
import * as fx from "./sfx.mjs";

const timing = JSON.parse(readFileSync(new URL("../src/film/timing.json", import.meta.url)));
const script = JSON.parse(readFileSync(new URL("../src/film/voice.json", import.meta.url)));
const manifest = JSON.parse(readFileSync(new URL("../src/film/voice-manifest.json", import.meta.url)));
const { mix } = script;

// The film's grid, as in src/film/grid.ts.
const BAR = timing.beat * 4;
const sec = {};
let frames = 0;
for (const s of timing.sections) { sec[s.name] = { from: frames, factor: (timing.baseBeat / timing.beat) * s.speed }; frames += s.bars * BAR; }
const at = (section, original) => (sec[section].from + original / sec[section].factor) / timing.fps;
const FILM = frames / timing.fps;
const LENGTH = FILM + 1.2;
const DROP = sec.workday.from / timing.fps;
const HALF_BEAT = timing.beat / timing.fps / 2;

// ── Cue sheet: [section, frame in that section's original timing, sound, level] ────────────────
reseed(11);
const cues = [];
const cue = (section, frame, sound, level = 1) => cues.push({ t: at(section, frame), sound, level });

// Opening words, each a note in the bar's chord, so the type reads as music rather than clicks.
[[0, 77], [8, 81], [15, 84], [22, 88], [60, 81], [68, 84], [75, 88], [83, 91]].forEach(([f, m]) => cue("hook", f, () => fx.word(m), 0.32));
// Into the screen; the hand heads for the notch; "here."; the notch rushing open into the drop.
cue("build", 0, () => fx.swish(0.5, 300, 1800), 0.16);
cue("build", 22, () => fx.swish(0.6, 400, 1600), 0.1);
cue("build", 96, () => fx.word(89), 0.3);
cue("build", 116, fx.open, 0.5);
// The workspace: cards arrive, the camera pushes in, a task gets ticked, the timer starts, it folds away.
cue("workday", 6, fx.shimmer, 0.24);
cue("workday", 22, () => fx.swish(0.6, 250, 1400), 0.16);
cue("workday", 42, () => fx.swish(0.35, 600, 2400), 0.1);
cue("workday", 90, fx.click, 0.5);
cue("workday", 92, fx.check, 0.4);
cue("workday", 95, fx.cheer, 0.26);
cue("workday", 100, () => fx.swish(0.35, 600, 2400), 0.1);
cue("workday", 150, fx.click, 0.5);
cue("workday", 152, fx.start, 0.3);
cue("workday", 165, fx.collapse, 0.42);
// The push into the island, and the clock on every beat.
cue("keeps", 0, () => fx.swish(0.7, 200, 1600), 0.2);
[0, 15, 30, 45].forEach((f) => cue("keeps", f, fx.tick, 0.24));
// "Or skip the mouse": the keycaps, the cut, the bar dropping, the typing, the pill.
cue("command", 0, () => fx.whip(true), 0.34);
cue("command", 30, fx.thock, 0.55);
cue("command", 45, fx.thock, 0.6);
cue("command", 60, () => fx.whip(false), 0.34);
cue("command", 61, () => fx.swish(0.25, 2400, 600), 0.14);
const typed = (section, text, from, to, level) => [...text].forEach((ch, k) => {
  if (ch === " ") cue(section, from + ((to - from) * (k + 1)) / text.length, fx.spacebar, level * 1.25);
  else cue(section, from + ((to - from) * (k + 1)) / text.length, fx.key, level);
});
typed("command", "call mika tomorrow at 3pm", 64, 100, 0.2);
cue("command", 104, fx.bubble, 0.26);
// The assistant: typing, sending, the cut, and three tasks landing as rising notes in the chord.
cue("ask", 0, () => fx.whip(true), 0.34);
typed("ask", "Add my three most urgent issues to today.", 4, 44, 0.17);
cue("ask", 50, fx.send, 0.38);
cue("ask", 60, () => fx.whip(false), 0.34);
[[62, 77], [74.7, 81], [87.3, 84]].forEach(([f, m]) => cue("ask", f, () => fx.note(m), 0.38));
// The montage: a whip on every cut, then "Free. Open source." in notes.
for (let i = 0; i < 8; i++) cue("montage", i * 15, () => fx.whip(i % 2 === 0), 0.3);
[[105, 84], [110, 88], [114, 91]].forEach(([f, m]) => cue("montage", f, () => fx.word(m), 0.3));
// The logo.
cue("end", 0, fx.logo, 0.42);

// ── Stems ──────────────────────────────────────────────────────────────────────────────────────
const music = readWavAt("public/audio/music.wav");
const musicStem = buf(LENGTH), voiceStem = buf(LENGTH), sfxStem = buf(LENGTH);

// Voice: rumble out, a little presence, even dynamics, then levelled by loudness.
const lines = manifest.lines.map((l) => {
  const v = readWavAt(`public/${l.file}`);
  biquad(v, "highpass", 90);
  biquad(v, "peak", 3500, 1, 2.5);
  biquad(v, "highshelf", 9000, 0.7, -2);
  compress(v, { threshold: -26, ratio: 3, attack: 0.004, release: 0.12 });
  const g = db(mix.voiceRms - rmsDb(v));
  for (let i = 0; i < v.length; i++) v[i] *= g;
  const t = l.from / timing.fps;
  place(voiceStem, v, t);
  return { t, end: t + v.length / SR, duck: l.duck };
});

// Gains over time: music dips per line; effects dip a little so typing never covers a word.
const ramp = (x, a, b) => Math.max(0, Math.min(1, (x - a) / (b - a)));
const gainAt = (t, deep) => {
  let g = 1;
  for (const l of lines) {
    const inside = Math.min(ramp(t, l.t - 0.15, l.t), 1 - ramp(t, l.end, l.end + 0.27));
    if (inside > 0) g = Math.min(g, 1 - inside * (1 - deep(l)));
  }
  return g;
};
for (let i = 0; i < musicStem.length && i < music.length; i++) musicStem[i] = music[i] * mix.music * gainAt(i / SR, (l) => l.duck);

for (const c of cues) place(sfxStem, c.sound(), c.t, c.level);
const wet = room(sfxStem, { size: 1.1, damp: 0.4, feedback: 0.76 });
for (let i = 0; i < sfxStem.length; i++) sfxStem[i] = (sfxStem[i] + wet[i] * 0.22) * gainAt(i / SR, () => db(-8));

// Room tone: faint, breathing, gone for the half-beat of silence before the drop.
const ambience = fx.air(LENGTH);
const target = db(-50 - rmsDb(ambience));
for (let i = 0; i < ambience.length; i++) {
  const t = i / SR;
  const gap = t > DROP - HALF_BEAT && t < DROP ? 0 : 1;
  ambience[i] *= target * Math.min(1, t / 0.6) * Math.min(1, Math.max(0, (FILM + 0.6 - t) / 1.2)) * gap;
}

// ── Master ─────────────────────────────────────────────────────────────────────────────────────
const out = buf(LENGTH);
for (let i = 0; i < out.length; i++) out[i] = musicStem[i] + voiceStem[i] + sfxStem[i] + ambience[i];
compress(out, { threshold: -16, ratio: 1.6, attack: 0.02, release: 0.25 });
let peak = 0;
for (const v of out) peak = Math.max(peak, Math.abs(v));
for (let i = 0; i < out.length; i++) out[i] *= 0.7 / peak;
writeWav("public/audio/premaster.wav", out);

// Two-pass loudness normalisation with the ffmpeg Remotion ships. ffmpeg reports on stderr.
const ffmpeg = (args) => {
  const r = spawnSync("npx", ["remotion", "ffmpeg", "-hide_banner", "-nostats", ...args], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`ffmpeg failed: ${r.stderr.slice(-400)}`);
  return r.stderr;
};
const loudness = (path) => {
  const text = ffmpeg(["-i", path, "-af", "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"]);
  return JSON.parse(text.slice(text.lastIndexOf("{"), text.lastIndexOf("}") + 1));
};
const measured = loudness("public/audio/premaster.wav");
ffmpeg(["-y", "-i", "public/audio/premaster.wav", "-af",
  `loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=${measured.input_i}:measured_TP=${measured.input_tp}:measured_LRA=${measured.input_lra}:measured_thresh=${measured.input_thresh}:offset=${measured.target_offset}:linear=true`,
  "-ar", String(SR), "public/audio/mix.wav"]);

// ── Report ─────────────────────────────────────────────────────────────────────────────────────
console.log(`${cues.length} cues over ${FILM.toFixed(2)}s`);
console.log("\nvoice over everything else (music + effects + room tone), per line:");
manifest.lines.forEach((l, i) => {
  const a = Math.floor(lines[i].t * SR), z = Math.floor(lines[i].end * SR);
  const bg = new Float32Array(z - a);
  for (let k = 0; k < bg.length; k++) bg[k] = musicStem[a + k] + sfxStem[a + k] + ambience[a + k];
  const clear = rmsDb(voiceStem, a, z) - rmsDb(bg);
  console.log(`  ${lines[i].t.toFixed(2).padStart(6)}s  +${clear.toFixed(1)} dB  ${script.lines[i]?.text ?? ""}`);
});
const done = loudness("public/audio/mix.wav");
console.log(`\nmaster: ${done.input_i} LUFS integrated, true peak ${done.input_tp} dBTP, loudness range ${done.input_lra} LU`);
