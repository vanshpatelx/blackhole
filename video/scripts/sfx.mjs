// Sound design for the film: every effect is synthesized here from scratch, no samples.
// Each function returns a fresh mono buffer at 48 kHz. `rand` makes repeats (keystrokes) differ.
import { SR, biquad, buf, db, midi, noise, rand } from "./lib/dsp.mjs";

const env = (t, attack, decay) => (t < attack ? t / attack : Math.exp(-(t - attack) * decay));

/** Band-limited noise burst: the core of anything that clicks, taps or rustles. */
function burst(seconds, center, q, decay, attack = 0.0005) {
  const o = buf(seconds);
  for (let i = 0; i < o.length; i++) o[i] = noise() * env(i / SR, attack, decay);
  return biquad(o, "bandpass", center, q);
}

function sine(seconds, f0, f1, decay, attack = 0.002) {
  const o = buf(seconds);
  let ph = 0;
  for (let i = 0; i < o.length; i++) {
    const t = i / SR;
    const f = f1 === undefined ? f0 : f0 * Math.pow(f1 / f0, Math.min(1, t / seconds));
    ph += (2 * Math.PI * f) / SR;
    o[i] = Math.sin(ph) * env(t, attack, decay);
  }
  return o;
}

const mixIn = (...parts) => {
  const n = Math.max(...parts.map(([b, at]) => b.length + Math.floor((at ?? 0) * SR)));
  const o = new Float32Array(n);
  for (const [b, at = 0, g = 1] of parts) { const s = Math.floor(at * SR); for (let i = 0; i < b.length; i++) o[s + i] += b[i] * g; }
  return o;
};

// ── Hands on hardware ──────────────────────────────────────────────────────────────────────────

/** A mouse click is two events: the press, and ~70ms later the softer, higher release. */
export const click = () => mixIn(
  [burst(0.03, 2600 + rand() * 300, 2.2, 260), 0, 1],
  [sine(0.03, 140, 90, 160), 0, 0.5],
  [burst(0.02, 3600 + rand() * 300, 2.6, 380), 0.065 + rand() * 0.015, 0.45]
);

/** A laptop keystroke: tap, a little body, and a quiet release. No two alike. */
export const key = () => {
  const body = 170 + rand() * 90;
  return mixIn(
    [burst(0.035, 1800 + rand() * 1400, 1.6, 220), 0, 0.8],
    [sine(0.04, body, body * 0.8, 120), 0, 0.35],
    [burst(0.02, 2800 + rand() * 900, 2, 400), 0.05 + rand() * 0.02, 0.25]
  );
};

/** The space bar: lower, longer, and it rattles slightly on its stabilizer. */
export const spacebar = () => mixIn(
  [burst(0.06, 1300, 1.2, 120), 0, 0.85],
  [burst(0.04, 1500, 1.4, 160), 0.008, 0.35],
  [sine(0.07, 125, 95, 70), 0, 0.5],
  [burst(0.03, 2200, 1.8, 260), 0.085, 0.3]
);

/** A big keycap on a desk-sized keyboard: the deep "thock" for the ⌥ and space shots. */
export const thock = () => mixIn(
  [sine(0.12, 155, 110, 38), 0, 0.9],
  [burst(0.05, 1100, 1.1, 90), 0, 0.6],
  [burst(0.03, 2600, 2, 300), 0.11, 0.3]
);

// ── Motion ─────────────────────────────────────────────────────────────────────────────────────

/** Air moving: a filtered-noise sweep with a soft swell. Used for the cursor and the camera. */
export function swish(seconds = 0.35, from = 500, to = 2600, level = 1) {
  const o = buf(seconds);
  let low = 0, band = 0;
  for (let i = 0; i < o.length; i++) {
    const p = i / o.length;
    const f = 2 * Math.sin((Math.PI * (from + (to - from) * p)) / SR);
    const x = noise();
    low += f * band; const high = x - low - 0.7 * band; band += f * high;
    o[i] = band * Math.sin(Math.PI * p) * Math.sin(Math.PI * p) * level;
  }
  return o;
}

/** Something landing softly: a short sub thump with a little body on top. */
export const land = () => mixIn([sine(0.25, 95, 48, 16), 0, 1], [burst(0.06, 380, 1, 60), 0, 0.3]);

/** The notch opening: air rushing up into a landing thump as the panel settles. */
export const open = () => mixIn([swish(0.42, 300, 3200, 1), 0, 1], [land(), 0.3, 0.8]);

/** Cards arriving: a few glassy high notes in the song's key, a few milliseconds apart. */
export const shimmer = () => mixIn(
  ...[89, 93, 96, 100].map((m, i) => [sine(0.5, midi(m), undefined, 9, 0.004), i * 0.035, 0.28])
);

/** Folding back into the notch: air sweeping down, then a soft pop. */
export const collapse = () => mixIn([swish(0.3, 2800, 400, 0.9), 0, 1], [sine(0.12, 900, 330, 30), 0.22, 0.6]);

/** A hard cut: a very short whip of air with a sharp front. */
export const whip = (high = true) => mixIn([swish(0.14, high ? 4200 : 3000, 600, 1.2), 0, 1], [burst(0.01, 3000, 1, 600), 0, 0.4]);

// ── Interface feedback ─────────────────────────────────────────────────────────────────────────

/** The check landing: two quick rising notes, bright, with the tick of the box. */
export const check = () => mixIn(
  [burst(0.015, 4000, 2, 500), 0, 0.4],
  [sine(0.18, midi(84), undefined, 22), 0.005, 0.5],
  [sine(0.3, midi(89), undefined, 14), 0.06, 0.6]
);

/** Holey cheering: a quick upward chirp with a wobble, and a sparkle after it. */
export function cheer() {
  const o = buf(0.16);
  let ph = 0;
  for (let i = 0; i < o.length; i++) {
    const t = i / SR, p = t / 0.16;
    const f = 620 + 900 * p + Math.sin(t * 2 * Math.PI * 28) * 40;
    ph += (2 * Math.PI * f) / SR;
    o[i] = Math.sin(ph) * Math.sin(Math.PI * p);
  }
  return mixIn([o, 0, 0.5], [shimmer(), 0.1, 0.5]);
}

/** Starting the timer: one soft bell-like pluck. */
export const start = () => mixIn([sine(0.6, midi(81), undefined, 7), 0, 0.5], [sine(0.6, midi(88), undefined, 9), 0.01, 0.2]);

/** A clock tick for the island close-up, on the beat. */
export const tick = () => mixIn([burst(0.02, 3400, 3, 450), 0, 0.9], [sine(0.02, 1800, undefined, 300), 0, 0.2]);

/** A word arriving: a soft plucked note, so the opening reads as music rather than clicks. */
export const word = (m) => mixIn([sine(0.35, midi(m), undefined, 16, 0.003), 0, 0.5], [sine(0.2, midi(m + 12), undefined, 30, 0.003), 0, 0.12]);

/** The pill under the typed command: a small bubble. */
export const bubble = () => sine(0.08, 520, 980, 40, 0.003);

/** Sending a message: the click of the button and a short rising whoosh. */
export const send = () => mixIn([click(), 0, 0.8], [swish(0.25, 800, 4200, 0.8), 0.02, 1]);

/** A task appearing in the list: a marimba-ish note. */
export const note = (m) => mixIn([sine(0.5, midi(m), undefined, 10, 0.002), 0, 0.6], [sine(0.2, midi(m) * 4, undefined, 40, 0.001), 0, 0.15]);

// ── The close ──────────────────────────────────────────────────────────────────────────────────

/** The logo: a bell, a low hit underneath it, and a sparkle on the way out. */
export function logo() {
  const bell = buf(2.4);
  for (let i = 0; i < bell.length; i++) {
    const t = i / SR;
    let v = 0;
    for (const [r, a, d] of [[1, 1, 2.2], [2.76, 0.5, 3.4], [5.4, 0.25, 5], [8.93, 0.12, 7]]) v += Math.sin(2 * Math.PI * midi(84) * r * t) * a * Math.exp(-t * d);
    bell[i] = v * Math.min(1, i / 60) * 0.5;
  }
  return mixIn([bell, 0, 1], [sine(0.9, 70, 38, 4), 0, 0.9], [shimmer(), 0.15, 0.4]);
}

// ── Room tone ──────────────────────────────────────────────────────────────────────────────────

/** A faint, slowly breathing air bed, so quiet moments sound like a room rather than digital zero. */
export function air(seconds) {
  const o = buf(seconds);
  let b0 = 0, b1 = 0, b2 = 0;
  for (let i = 0; i < o.length; i++) {
    const w = noise();
    // Paul Kellet's pink-noise filter.
    b0 = 0.99765 * b0 + w * 0.099046; b1 = 0.963 * b1 + w * 0.2965164; b2 = 0.57 * b2 + w * 1.0526913;
    const breathe = 0.85 + 0.15 * Math.sin((2 * Math.PI * i) / (SR * 9));
    o[i] = (b0 + b1 + b2 + w * 0.1848) * 0.06 * breathe;
  }
  biquad(o, "highpass", 140);
  biquad(o, "lowpass", 4200);
  return o;
}

export const level = db; // re-exported for the mixer's cue table

// ── The opening: a scattered day, then the pull ───────────────────────────────────────────────

/** The very first frame: a hit that says something has started. Low thump, bright crack, a tail. */
export const impact = () => mixIn(
  [sine(0.7, 110, 42, 5.5), 0, 1],
  [burst(0.04, 2400, 0.9, 120), 0, 0.7],
  [burst(0.5, 900, 0.6, 7), 0, 0.25]
);

/** Something landing on the pile: a soft pop pitched to the chord, so the clutter is still in key. */
export const pop = (m) => mixIn([sine(0.14, midi(m) * 1.5, midi(m), 26, 0.001), 0, 0.7], [burst(0.012, 3000, 2, 500), 0, 0.3]);

/** A notification: two quick tones, the second higher. */
export const ding = () => mixIn([sine(0.35, midi(88), undefined, 11, 0.002), 0, 0.5], [sine(0.45, midi(93), undefined, 9, 0.002), 0.09, 0.55]);

/** A phone buzzing against a desk. */
export function buzz() {
  const o = buf(0.42);
  for (let i = 0; i < o.length; i++) {
    const t = i / SR;
    const on = Math.sin(2 * Math.PI * 7 * t) > -0.2 ? 1 : 0; // two short pulses
    o[i] = (Math.sin(2 * Math.PI * 155 * t) * 0.8 + Math.sin(2 * Math.PI * 310 * t) * 0.25) * on * Math.sin((Math.PI * t) / 0.42);
  }
  return biquad(o, "highpass", 90);
}

/** Air spiralling into the hole: a rising, whirling sweep. The mixer swings it left and right. */
export function swirl(seconds = 1.6) {
  const o = buf(seconds);
  let low = 0, band = 0;
  for (let i = 0; i < o.length; i++) {
    const p = i / o.length;
    const whirl = 1 + 0.35 * Math.sin(2 * Math.PI * (3 + 9 * p) * (i / SR)); // speeding up as it tightens
    const fc = (250 + 3200 * p * p) * whirl;
    const f = 2 * Math.sin((Math.PI * Math.min(fc, 9000)) / SR);
    const x = noise();
    low += f * band; const high = x - low - 0.55 * band; band += f * high;
    o[i] = band * Math.pow(p, 1.4) * 1.1;
  }
  return o;
}

/** A low tone falling away underneath the pull — the floor dropping out. */
export const sink = (seconds = 1.6) => sine(seconds, 120, 34, 0.6, 0.25);

/** The hole closing: everything sucked in at once, then cut. */
export function implode() {
  const o = buf(0.5);
  for (let i = 0; i < o.length; i++) {
    const t = i / SR, p = t / 0.5;
    // A reversed swell: grows fast, then stops dead — the sound of something being taken away.
    o[i] = noise() * Math.pow(p, 3) * (p < 0.96 ? 1 : (1 - p) / 0.04);
  }
  biquad(o, "bandpass", 1400, 0.6);
  return mixIn([o, 0, 1], [sine(0.3, 70, 30, 12), 0.47, 1]);
}
