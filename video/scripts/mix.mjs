// The final mix: music, voiceover, sound effects and room tone, placed on the film's beat grid,
// processed in stereo, and mastered to -14 LUFS (what X, LinkedIn and YouTube normalise towards).
//
//   node scripts/mix.mjs   →   public/audio/mix.wav   (run audio.mjs and voice.mjs first)
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { SR, biquad, buf, db, placeStereo, rand, readWavAt, readWavStereo, reseed, rmsDb, room, splitThree, writeWav, writeWavStereo } from "./lib/dsp.mjs";
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

// ── Cue sheet ──────────────────────────────────────────────────────────────────────────────────
// [section, frame in that section's original timing, sound, level, pan]. Pan follows where the
// thing happens on screen: the task list is on the left, the send button on the right, and so on.
reseed(11);
const cues = [];
const cue = (section, frame, sound, level = 1, p = 0) => cues.push({ t: at(section, frame), sound, level, p });
const wordPan = (m) => Math.max(-0.5, Math.min(0.5, (m - 86) / 10));

// The opening is spoken now, so the per-word notes that used to mark each word are gone from under
// it: they sat in exactly the frequencies her words need. "here." lands after the line ends.
cue("build", 0, () => fx.swish(0.5, 300, 1800), 0.16, 0);
cue("build", 22, () => fx.swish(0.6, 400, 1600), 0.1, 0.4); // the hand enters from the right
cue("build", 96, () => fx.word(89), 0.3, wordPan(89));
cue("build", 116, fx.open, 0.5, 0);
// The workspace: cards arrive, the camera pushes in, a task gets ticked, the timer starts, it folds away.
cue("workday", 6, fx.shimmer, 0.24, 0);
cue("workday", 22, () => fx.swish(0.6, 250, 1400), 0.16, 0);
cue("workday", 42, () => fx.swish(0.35, 600, 2400), 0.1, -0.35); // heading left, to the task
cue("workday", 90, fx.click, 0.5, -0.6); // the task list is on the left
cue("workday", 92, fx.check, 0.4, -0.6);
cue("workday", 95, fx.cheer, 0.26, -0.75); // Holey, top left
cue("workday", 100, () => fx.swish(0.35, 600, 2400), 0.1, -0.3);
cue("workday", 150, fx.click, 0.5, -0.15); // the Start button, just left of centre
cue("workday", 152, fx.start, 0.3, -0.15);
cue("workday", 165, fx.collapse, 0.42, 0);
// The push into the island, and the clock on every beat.
cue("keeps", 0, () => fx.swish(0.7, 200, 1600), 0.2, 0);
[0, 15, 30, 45].forEach((f) => cue("keeps", f, fx.tick, 0.24, 0));
// "Or skip the mouse": the keycaps, the cut, the bar dropping, the typing, the pill.
cue("command", 0, () => fx.whip(true), 0.34, -0.3);
cue("command", 30, fx.thock, 0.55, -0.25); // ⌥ sits left of the space bar
cue("command", 45, fx.thock, 0.6, 0.15);
cue("command", 60, () => fx.whip(false), 0.34, 0.3);
cue("command", 61, () => fx.swish(0.25, 2400, 600), 0.14, 0);
const typed = (section, text, from, to, level) => [...text].forEach((ch, k) => {
  const t = from + ((to - from) * (k + 1)) / text.length;
  // A keyboard is wide: letters spread a little across it, the space bar sits in the middle.
  if (ch === " ") cue(section, t, fx.spacebar, level * 1.25, 0);
  else cue(section, t, fx.key, level, (rand() - 0.5) * 0.3);
});
typed("command", "call mika tomorrow at 3pm", 64, 100, 0.2);
cue("command", 104, fx.bubble, 0.26, 0.35); // the pill is at the right of the bar
// The assistant: typing, sending, the cut, and three tasks landing as rising notes in the chord.
cue("ask", 0, () => fx.whip(true), 0.34, -0.3);
typed("ask", "Add my three most urgent issues to today.", 4, 44, 0.17);
cue("ask", 50, fx.send, 0.38, 0.35); // the send button is on the right
cue("ask", 60, () => fx.whip(false), 0.34, 0.3);
[[62, 77], [74.7, 81], [87.3, 84]].forEach(([f, m]) => cue("ask", f, () => fx.note(m), 0.38, -0.4)); // the task list, on the left
// The montage: a whip on every cut, swinging side to side, then "Free. Open source." in notes.
for (let i = 0; i < 8; i++) cue("montage", i * 15, () => fx.whip(i % 2 === 0), 0.3, i % 2 === 0 ? -0.35 : 0.35);
[[105, 84], [110, 88], [114, 91]].forEach(([f, m]) => cue("montage", f, () => fx.word(m), 0.3, wordPan(m)));
// The logo.
cue("end", 0, fx.logo, 0.42, 0);

// ── Voice: dead centre, rumble out, a little presence, even dynamics, levelled by loudness ──────
const voice = buf(LENGTH);
const lines = manifest.lines.map((l) => {
  const v = readWavAt(`public/${l.file}`);
  biquad(v, "highpass", 90);
  biquad(v, "peak", 3500, 1, 2.5);
  biquad(v, "highshelf", 9000, 0.7, -2);
  compressMono(v, { threshold: -26, ratio: 3, attack: 0.004, release: 0.12 });
  const g = db(mix.voiceRms - rmsDb(v));
  const t = l.from / timing.fps;
  for (let i = 0; i < v.length; i++) { const j = Math.floor(t * SR) + i; if (j < voice.length) voice[j] += v[i] * g; }
  return { t, end: t + v.length / SR, duck: l.duck };
});

// How deep something dips while she is speaking, eased in and out around each line.
const ramp = (x, a, b) => Math.max(0, Math.min(1, (x - a) / (b - a)));
const dipAt = (t, depth) => {
  let g = 1;
  for (const l of lines) {
    const inside = Math.min(ramp(t, l.t - 0.15, l.t), 1 - ramp(t, l.end, l.end + 0.27));
    if (inside > 0) g = Math.min(g, 1 - inside * (1 - depth(l)));
  }
  return g;
};
const speechDip = db(-mix.speechBandDip);

/**
 * Dips a stereo pair under the voice: broadband by `depth`, and further in 1–4 kHz, where words are
 * understood. Splitting into three bands that always sum back exactly means that outside a line this
 * changes nothing at all.
 */
function duckUnderVoice(L, R, depth) {
  for (const ch of [L, R]) {
    const { low, mid, high } = splitThree(ch, 1000, 4000);
    for (let i = 0; i < ch.length; i++) {
      const t = i / SR;
      ch[i] = (low[i] + high[i] + mid[i] * dipAt(t, () => speechDip)) * dipAt(t, depth);
    }
  }
}

// ── Music: re-balanced, then out of the voice's way ────────────────────────────────────────────
const m = readWavStereo("public/audio/music.wav");
if (m.sr !== SR) throw new Error(`music is ${m.sr} Hz, expected ${SR}`);
const musicL = buf(LENGTH), musicR = buf(LENGTH);
musicL.set(m.L.subarray(0, LENGTH * SR)); musicR.set(m.R.subarray(0, LENGTH * SR));
for (const ch of [musicL, musicR]) {
  biquad(ch, "highpass", 35, 0.707);           // rumble no phone can play
  biquad(ch, "lowshelf", 180, 0.707, -3);      // less boom
  biquad(ch, "peak", 300, 1, -2);              // less mud
  biquad(ch, "highshelf", 5000, 0.707, 3);     // a little air
  for (let i = 0; i < ch.length; i++) ch[i] *= mix.music;
}
duckUnderVoice(musicL, musicR, (l) => l.duck);

// ── Effects: placed and panned, in one stereo room, peaks held, out of the voice's way ──────────
const sfxL = buf(LENGTH), sfxR = buf(LENGTH);
for (const c of cues) placeStereo(sfxL, sfxR, c.sound(), c.t, c.level, c.p);
const wetL = room(sfxL, { size: 1.1, damp: 0.4, feedback: 0.76 }), wetR = room(sfxR, { size: 1.18, damp: 0.4, feedback: 0.76 });
for (let i = 0; i < sfxL.length; i++) { sfxL[i] += wetL[i] * 0.22; sfxR[i] += wetR[i] * 0.22; }
compressLinked(sfxL, sfxR, { threshold: -12, ratio: 4, attack: 0.001, release: 0.08 }); // hits stay punchy, never spiky
duckUnderVoice(sfxL, sfxR, () => db(-8));

// ── Room tone: two independent beds, so it has width; gone for the silence before the drop ──────
const ambL = fx.air(LENGTH), ambR = fx.air(LENGTH);
for (const ch of [ambL, ambR]) {
  const target = db(-50 - rmsDb(ch));
  for (let i = 0; i < ch.length; i++) {
    const t = i / SR;
    const gap = t > DROP - HALF_BEAT && t < DROP ? 0 : 1;
    ch[i] *= target * Math.min(1, t / 0.6) * Math.min(1, Math.max(0, (FILM + 0.6 - t) / 1.2)) * gap;
  }
}

// ── Master ─────────────────────────────────────────────────────────────────────────────────────
const outL = buf(LENGTH), outR = buf(LENGTH);
for (let i = 0; i < outL.length; i++) {
  outL[i] = musicL[i] + voice[i] + sfxL[i] + ambL[i];
  outR[i] = musicR[i] + voice[i] + sfxR[i] + ambR[i];
}
biquad(outL, "highpass", 30, 0.707); biquad(outR, "highpass", 30, 0.707);
compressLinked(outL, outR, { threshold: -16, ratio: 1.6, attack: 0.02, release: 0.25 });
let peak = 0;
for (let i = 0; i < outL.length; i++) peak = Math.max(peak, Math.abs(outL[i]), Math.abs(outR[i]));
for (let i = 0; i < outL.length; i++) { outL[i] *= 0.7 / peak; outR[i] *= 0.7 / peak; }
writeWavStereo("public/audio/premaster.wav", outL, outR);

// Stems, for inspecting the mix layer by layer (scripts/analyze.mjs reads them).
mkdirSync("out/stems", { recursive: true });
writeWavStereo("out/stems/music.wav", musicL, musicR);
writeWav("out/stems/voice.wav", voice);
writeWavStereo("out/stems/sfx.wav", sfxL, sfxR);
writeWavStereo("out/stems/ambience.wav", ambL, ambR);

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
const done = loudness("public/audio/mix.wav");
console.log(`${cues.length} cues over ${FILM.toFixed(2)}s, stereo`);
console.log(`master: ${done.input_i} LUFS integrated, true peak ${done.input_tp} dBTP, loudness range ${done.input_lra} LU`);

// ── Dynamics ───────────────────────────────────────────────────────────────────────────────────
function compressMono(d, o) { compressLinked(d, null, o); }
/** Feed-forward compression; with two channels the gain is shared, so the image never shifts. */
function compressLinked(L, R, { threshold = -20, ratio = 3, attack = 0.005, release = 0.12, makeup = 0 } = {}) {
  const ga = Math.exp(-1 / (attack * SR)), gr = Math.exp(-1 / (release * SR));
  let env = 0;
  for (let i = 0; i < L.length; i++) {
    const level = R ? Math.max(Math.abs(L[i]), Math.abs(R[i])) : Math.abs(L[i]);
    env = level > env ? ga * env + (1 - ga) * level : gr * env + (1 - gr) * level;
    const over = Math.max(0, 20 * Math.log10(env + 1e-9) - threshold);
    const g = db(-over * (1 - 1 / ratio) + makeup);
    L[i] *= g;
    if (R) R[i] *= g;
  }
}
