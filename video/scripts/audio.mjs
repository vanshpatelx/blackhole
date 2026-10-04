// Synthesizes the film's soundtrack and sound effects from nothing: no samples, no loops, no
// borrowed music. Everything here is an original composition, so the film is free to post anywhere.
//
//   node scripts/audio.mjs   →   public/audio/*.wav
//
// 120 BPM, so a beat is 0.5s (15 frames at 30fps) and a bar is 2s. The film cuts on these.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

// Tempo and arrangement come from the same file the film is cut from, so the two can't drift.
const timing = JSON.parse(readFileSync(new URL("../src/film/timing.json", import.meta.url)));
// 48 kHz, the rate the video carries, so the mix never has to resample the music.
const SR = 48000;
const BEAT = timing.beat / timing.fps; // seconds
const BPM = 60 / BEAT;
const BAR = BEAT * 4;
const barStart = {};
let BARS = 0;
for (const { name, bars } of timing.sections) { barStart[name] = BARS; BARS += bars; }
const DROP = barStart.workday; // the notch opens on this bar
const PEAK = [barStart.montage, barStart.end]; // [from, to)
const OUTRO = barStart.end;
const LENGTH = BAR * BARS + 1.5; // a little tail for the last chord to ring

// A seeded generator, so every render produces the identical file and diffs stay meaningful.
let seed = 7;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const noise = () => rand() * 2 - 1;
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
const buf = (seconds) => new Float32Array(Math.ceil(seconds * SR));

function writeWav(path, data) {
  const out = Buffer.alloc(44 + data.length * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + data.length * 2, 4); out.write("WAVE", 8);
  out.write("fmt ", 12); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write("data", 36); out.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, data[i])) * 32767), 44 + i * 2);
  writeFileSync(path, out);
}

function normalize(data, peak = 0.89) {
  let max = 0;
  for (const v of data) max = Math.max(max, Math.abs(v));
  if (max > 0) for (let i = 0; i < data.length; i++) data[i] *= peak / max;
  return data;
}

// --- Instruments -----------------------------------------------------------------------------

/** Karplus–Strong: a plucked string. It's what makes the motif sound played rather than generated. */
function pluck(out, start, freq, amp, seconds = 1.6) {
  const n = Math.max(2, Math.round(SR / freq));
  const ring = new Float32Array(n);
  let lp = 0;
  for (let i = 0; i < n; i++) { lp += 0.5 * (noise() - lp); ring[i] = lp; }
  const s0 = Math.floor(start * SR);
  const len = Math.floor(seconds * SR);
  for (let i = 0, k = 0; i < len && s0 + i < out.length; i++) {
    const a = ring[k];
    const b = ring[(k + 1) % n];
    ring[k] = 0.4985 * (a + b);
    out[s0 + i] += a * amp;
    k = (k + 1) % n;
  }
}

/** A warm pad: a few detuned voices with soft harmonics, slow in and slow out. */
function pad(out, start, seconds, notes, amp) {
  const s0 = Math.floor(start * SR);
  const len = Math.floor((seconds + 0.8) * SR);
  const attack = 0.45 * SR, release = 0.8 * SR, hold = seconds * SR;
  for (const m of notes) {
    for (const cents of [-7, 0, 6]) {
      const f = midi(m) * Math.pow(2, cents / 1200);
      for (let i = 0; i < len && s0 + i < out.length; i++) {
        const env = i < attack ? i / attack : i < hold ? 1 : Math.max(0, 1 - (i - hold) / release);
        const t = i / SR;
        let v = 0;
        for (let h = 1; h <= 5; h++) v += Math.sin(2 * Math.PI * f * h * t) / Math.pow(h, 1.6);
        out[s0 + i] += v * env * amp;
      }
    }
  }
}

function bass(out, start, seconds, m, amp) {
  const s0 = Math.floor(start * SR);
  const len = Math.floor(seconds * SR);
  const f = midi(m);
  for (let i = 0; i < len && s0 + i < out.length; i++) {
    const t = i / SR;
    const env = Math.min(1, i / (0.01 * SR)) * Math.exp(-t * 2.2);
    out[s0 + i] += (Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(4 * Math.PI * f * t)) * env * amp;
  }
}

function kick(out, start, amp) {
  const s0 = Math.floor(start * SR);
  let phase = 0;
  for (let i = 0; i < 0.45 * SR && s0 + i < out.length; i++) {
    const t = i / SR;
    const f = 45 + 105 * Math.exp(-t * 28);
    phase += (2 * Math.PI * f) / SR;
    out[s0 + i] += (Math.sin(phase) * Math.exp(-t * 7) + noise() * Math.exp(-t * 300) * 0.25) * amp;
  }
}

function clap(out, start, amp) {
  const s0 = Math.floor(start * SR);
  let low = 0, band = 0;
  const f = 2 * Math.sin((Math.PI * 1500) / SR);
  for (let i = 0; i < 0.22 * SR && s0 + i < out.length; i++) {
    const t = i / SR;
    // Three quick bursts then a tail: the shape of hands, roughly.
    const burst = t < 0.01 ? 1 : t < 0.02 ? 0.6 : t < 0.03 ? 0.85 : Math.exp(-(t - 0.03) * 22);
    const x = noise();
    low += f * band; const high = x - low - 0.6 * band; band += f * high;
    out[s0 + i] += band * burst * amp;
  }
}

function hat(out, start, amp, open = false) {
  const s0 = Math.floor(start * SR);
  let lp = 0;
  const decay = open ? 18 : 70;
  for (let i = 0; i < (open ? 0.25 : 0.07) * SR && s0 + i < out.length; i++) {
    const x = noise();
    lp += 0.6 * (x - lp);
    out[s0 + i] += (x - lp) * Math.exp(-(i / SR) * decay) * amp;
  }
}

/** Filtered noise that opens up and swells: the lift into the moment the notch opens. */
function riser(out, start, seconds, amp) {
  const s0 = Math.floor(start * SR);
  const len = Math.floor(seconds * SR);
  let low = 0, band = 0;
  for (let i = 0; i < len && s0 + i < out.length; i++) {
    const p = i / len;
    const fc = 300 + 5000 * p * p;
    const f = 2 * Math.sin((Math.PI * fc) / SR);
    const x = noise();
    low += f * band; const high = x - low - 0.5 * band; band += f * high;
    out[s0 + i] += band * p * p * amp;
  }
}

/** Schroeder reverb: a few combs and allpasses. Enough room to stop the plucks sounding dry. */
function reverb(input, wet = 0.3) {
  const out = new Float32Array(input.length);
  const combs = [29.7, 37.1, 41.1, 43.7].map((ms) => ({ d: Math.floor((ms / 1000) * SR), b: null, i: 0 }));
  for (const c of combs) c.b = new Float32Array(c.d);
  for (let n = 0; n < input.length; n++) {
    let s = 0;
    for (const c of combs) { const y = c.b[c.i]; c.b[c.i] = input[n] + y * 0.8; c.i = (c.i + 1) % c.d; s += y; }
    out[n] = s / 4;
  }
  for (const ms of [5.0, 1.7]) {
    const d = Math.floor((ms / 1000) * SR);
    const b = new Float32Array(d);
    let i = 0;
    for (let n = 0; n < out.length; n++) { const y = b[i]; const x = out[n]; b[i] = x + y * 0.7; out[n] = y - 0.7 * x; i = (i + 1) % d; }
  }
  for (let n = 0; n < input.length; n++) out[n] = input[n] * (1 - wet) + out[n] * wet;
  return out;
}

// --- The piece -------------------------------------------------------------------------------

// Fmaj9 · Am7 · Dm9 · B♭maj7 — warm and lifting, one chord a bar.
const chords = [
  { pad: [53, 57, 60, 64, 67], root: 41, tones: [65, 69, 72, 76, 79] },
  { pad: [57, 60, 64, 67], root: 45, tones: [69, 72, 76, 79, 81] },
  { pad: [50, 53, 57, 60, 64], root: 50, tones: [62, 65, 69, 72, 76] },
  { pad: [58, 62, 65, 69], root: 46, tones: [70, 74, 77, 81, 82] }
];
const motif = [0, 2, 1, 3, 2, 4, 3, 1];
const humanize = () => (rand() - 0.5) * 0.016; // ±8ms: the difference between played and quantized

const music = buf(LENGTH);
const melodic = buf(LENGTH); // gets reverb
const drums = buf(LENGTH);
const kicks = [];

for (let bar = 0; bar < BARS; bar++) {
  const t0 = bar * BAR;
  const c = chords[bar % 4];
  const hook = bar < barStart.build, build = bar < DROP, groove = bar >= DROP && bar < OUTRO;
  const peak = bar >= PEAK[0] && bar < PEAK[1], outro = bar >= OUTRO;

  if (bar < OUTRO + 1) pad(music, t0, BAR, c.pad, hook ? 0.009 : build ? 0.008 : 0.014);

  // The motif: sparse under the opening words so they land clean, full once the notch opens.
  for (let step = 0; step < 8; step++) {
    if (hook && step % 2 === 1) continue;
    if (outro) continue;
    const note = c.tones[motif[step] % c.tones.length];
    const vel = (step % 2 === 0 ? 0.55 : 0.4) * (0.85 + rand() * 0.3) * (build ? 0.75 : 1);
    pluck(melodic, t0 + step * (BEAT / 2) + humanize(), midi(note), vel);
    // The montage is the energy peak, so the motif doubles an octave up there.
    if (peak) pluck(melodic, t0 + step * (BEAT / 2) + humanize(), midi(note + 12), vel * 0.45);
  }

  if (!build && !outro) {
    for (let b = 0; b < 4; b++) bass(music, t0 + b * BEAT, BEAT * 0.95, c.root, 0.32);
  }

  if (groove) {
    for (const b of [0, 2]) { kick(drums, t0 + b * BEAT, 0.95); kicks.push(t0 + b * BEAT); }
    if (bar % 2 === 1) { kick(drums, t0 + 2.5 * BEAT, 0.6); kicks.push(t0 + 2.5 * BEAT); }
    for (const b of [1, 3]) clap(drums, t0 + b * BEAT + humanize() * 0.5, peak ? 0.68 : 0.5);
    const div = peak ? 4 : 2;
    for (let h = 0; h < 4 * div; h++) {
      const accent = h % div === div / 2 ? 0.32 : 0.16;
      hat(drums, t0 + (h * BEAT) / div + humanize() * 0.4, accent, peak && h === 4 * div - 1);
    }
  }
}

// The lift into the drop, across the build.
riser(drums, barStart.build * BAR, (DROP - barStart.build) * BAR - BEAT / 2, 0.2);
const dropAt = DROP * BAR;

// A final chord that rings out under the end card.
pad(music, OUTRO * BAR, BAR * (BARS - OUTRO) - 0.4, [53, 57, 60, 64, 67, 72], 0.010);
for (const [i, m] of [65, 69, 72, 76, 79, 84].entries()) pluck(melodic, OUTRO * BAR + i * 0.06, midi(m), 0.32, 3);

// Sidechain: everything melodic ducks under each kick, which is what makes it breathe.
const duck = new Float32Array(music.length).fill(1);
for (const k of kicks) {
  const s0 = Math.floor(k * SR);
  for (let i = 0; i < 0.22 * SR && s0 + i < duck.length; i++) duck[s0 + i] = Math.min(duck[s0 + i], 0.5 + 0.5 * (i / (0.22 * SR)));
}

const wet = reverb(melodic, 0.32);
const mix = buf(LENGTH);
for (let i = 0; i < mix.length; i++) mix[i] = (music[i] + wet[i] * 0.9) * duck[i] + drums[i] * 0.9;

// Half a beat of silence before the drop, so the notch opens out of nothing. The drop kick is
// written after this, so it still hits.
{
  const gapStart = Math.floor((DROP * BAR - BEAT / 2) * SR), gapEnd = Math.floor(DROP * BAR * SR), ramp = Math.floor(0.03 * SR);
  for (let i = gapStart; i < gapEnd; i++) mix[i] *= i < gapStart + ramp ? 1 - (i - gapStart) / ramp : 0;
}
kick(mix, dropAt, 1.25);
for (let i = 0; i < 0.9 * SR; i++) mix[Math.floor(dropAt * SR) + i] += noise() * Math.exp(-(i / SR) * 5) * 0.14;

// Automation: the montage is the energy peak, so it sits about 3 dB above the groove.
{
  const a = Math.floor(PEAK[0] * BAR * SR), z = Math.floor(PEAK[1] * BAR * SR), ramp = Math.floor(0.25 * SR);
  for (let i = a; i < z + ramp && i < mix.length; i++) {
    const up = i < a + ramp ? (i - a) / ramp : i < z ? 1 : 1 - (i - z) / ramp;
    mix[i] *= 1 + 0.42 * up;
  }
}

// Strip the DC offset the asymmetric kick leaves behind.
{
  let x1 = 0, y1 = 0;
  const r = 1 - (2 * Math.PI * 20) / SR;
  for (let i = 0; i < mix.length; i++) { const y = mix[i] - x1 + r * y1; x1 = mix[i]; y1 = y; mix[i] = y; }
}
const fadeStart = Math.floor((LENGTH - 1.2) * SR);
for (let i = 0; i < mix.length; i++) {
  // Saturate harder than a gentle clip: denser, so it holds up on phone speakers.
  mix[i] = Math.tanh(mix[i] * 2.1) / Math.tanh(2.1);
  if (i > fadeStart) mix[i] *= 1 - (i - fadeStart) / (mix.length - fadeStart);
}

// Sound effects live in scripts/sfx.mjs and are placed by scripts/mix.mjs.

mkdirSync("public/audio", { recursive: true });
writeWav("public/audio/music.wav", normalize(mix, 0.89));
console.log(`music ${LENGTH.toFixed(1)}s, ${BARS} bars at ${BPM.toFixed(2)} BPM (drop on bar ${DROP + 1})`);
