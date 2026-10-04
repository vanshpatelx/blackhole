// Small DSP toolkit shared by the soundtrack, sound-effect and mix scripts. Everything runs at one
// rate, 48 kHz, which is what the video carries; anything that arrives at another rate is resampled.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

export const SR = 48000;

let seed = 7;
export const reseed = (s) => { seed = s >>> 0; };
export const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
export const noise = () => rand() * 2 - 1;
export const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
export const buf = (seconds) => new Float32Array(Math.max(1, Math.ceil(seconds * SR)));
export const db = (x) => Math.pow(10, x / 20);

export function writeWav(path, data, sr = SR) {
  const out = Buffer.alloc(44 + data.length * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + data.length * 2, 4); out.write("WAVE", 8);
  out.write("fmt ", 12); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(sr, 24); out.writeUInt32LE(sr * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write("data", 36); out.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, data[i])) * 32767), 44 + i * 2);
  writeFileSync(path, out);
}

/** Reads a mono or stereo 16-bit/float WAV, downmixed to mono. */
export function readWav(path) {
  const b = readFileSync(path);
  let off = 12, fmt = null;
  while (off < b.length) {
    const id = b.toString("ascii", off, off + 4), size = b.readUInt32LE(off + 4);
    if (id === "fmt ") fmt = { ch: b.readUInt16LE(off + 10), sr: b.readUInt32LE(off + 12), bits: b.readUInt16LE(off + 22), tag: b.readUInt16LE(off + 8) };
    if (id === "data") {
      const bytes = fmt.bits / 8, frames = Math.floor(size / (bytes * fmt.ch)), d = new Float32Array(frames);
      for (let i = 0; i < frames; i++) {
        let v = 0;
        for (let c = 0; c < fmt.ch; c++) {
          const p = off + 8 + (i * fmt.ch + c) * bytes;
          v += fmt.bits === 16 ? b.readInt16LE(p) / 32768 : b.readFloatLE(p);
        }
        d[i] = v / fmt.ch;
      }
      return { sr: fmt.sr, data: d };
    }
    off += 8 + size + (size % 2);
  }
  throw new Error(`no audio in ${path}`);
}

/** Resamples with ffmpeg (Remotion ships one), so no separate install is needed. */
export function readWavAt(path, sr = SR) {
  const w = readWav(path);
  if (w.sr === sr) return w.data;
  const tmp = `${path}.${sr}.wav`;
  execFileSync("npx", ["remotion", "ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ar", String(sr), "-ac", "1", tmp]);
  return readWav(tmp).data;
}

export function normalize(data, peak = 0.89) {
  let max = 0;
  for (const v of data) max = Math.max(max, Math.abs(v));
  if (max > 0) for (let i = 0; i < data.length; i++) data[i] *= peak / max;
  return data;
}

export const rmsDb = (d, a = 0, z = d.length) => {
  let s = 0;
  for (let i = a; i < z; i++) s += d[i] * d[i];
  return 20 * Math.log10(Math.sqrt(s / Math.max(1, z - a)) + 1e-9);
};

/** RBJ biquad, applied in place. type: lowpass | highpass | bandpass | peak | highshelf | lowshelf */
export function biquad(d, type, f0, q = 0.707, gainDb = 0) {
  const A = Math.pow(10, gainDb / 40), w = (2 * Math.PI * f0) / SR, c = Math.cos(w), s = Math.sin(w), al = s / (2 * q);
  let b0, b1, b2, a0, a1, a2;
  if (type === "lowpass") { b0 = (1 - c) / 2; b1 = 1 - c; b2 = b0; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
  else if (type === "highpass") { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = b0; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
  else if (type === "bandpass") { b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al; }
  else if (type === "peak") { b0 = 1 + al * A; b1 = -2 * c; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * c; a2 = 1 - al / A; }
  else if (type === "highshelf") { const r = 2 * Math.sqrt(A) * al; b0 = A * ((A + 1) + (A - 1) * c + r); b1 = -2 * A * ((A - 1) + (A + 1) * c); b2 = A * ((A + 1) + (A - 1) * c - r); a0 = (A + 1) - (A - 1) * c + r; a1 = 2 * ((A - 1) - (A + 1) * c); a2 = (A + 1) - (A - 1) * c - r; }
  else { const r = 2 * Math.sqrt(A) * al; b0 = A * ((A + 1) - (A - 1) * c + r); b1 = 2 * A * ((A - 1) - (A + 1) * c); b2 = A * ((A + 1) - (A - 1) * c - r); a0 = (A + 1) + (A - 1) * c + r; a1 = -2 * ((A - 1) + (A + 1) * c); a2 = (A + 1) + (A - 1) * c - r; }
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < d.length; i++) {
    const x = d[i], y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x; y2 = y1; y1 = y; d[i] = y;
  }
  return d;
}

/** A feed-forward compressor with a smooth envelope. Threshold and makeup in dB. */
export function compress(d, { threshold = -20, ratio = 3, attack = 0.005, release = 0.12, makeup = 0 } = {}) {
  const ga = Math.exp(-1 / (attack * SR)), gr = Math.exp(-1 / (release * SR));
  let env = 0;
  for (let i = 0; i < d.length; i++) {
    const level = Math.abs(d[i]);
    env = level > env ? ga * env + (1 - ga) * level : gr * env + (1 - gr) * level;
    const lvl = 20 * Math.log10(env + 1e-9);
    const over = Math.max(0, lvl - threshold);
    d[i] *= db(-over * (1 - 1 / ratio) + makeup);
  }
  return d;
}

/** Schroeder-style room: a few combs and allpasses, returning only the wet signal. */
export function room(input, { size = 1, damp = 0.35, feedback = 0.78 } = {}) {
  const out = new Float32Array(input.length);
  const combs = [29.7, 37.1, 41.1, 43.7].map((ms) => { const n = Math.floor((ms * size / 1000) * SR); return { d: n, b: new Float32Array(n), i: 0, lp: 0 }; });
  for (let n = 0; n < input.length; n++) {
    let s = 0;
    for (const c of combs) {
      const y = c.b[c.i];
      c.lp = y * (1 - damp) + c.lp * damp;
      c.b[c.i] = input[n] + c.lp * feedback;
      c.i = (c.i + 1) % c.d;
      s += y;
    }
    out[n] = s / combs.length;
  }
  for (const ms of [5.0, 1.7]) {
    const d = Math.floor((ms / 1000) * SR), b = new Float32Array(d);
    let i = 0;
    for (let n = 0; n < out.length; n++) { const y = b[i], x = out[n]; b[i] = x + y * 0.7; out[n] = y - 0.7 * x; i = (i + 1) % d; }
  }
  return out;
}

/** Adds `src` into `dst` at `seconds`, scaled by `gain`. */
export function place(dst, src, seconds, gain = 1) {
  const s0 = Math.floor(seconds * SR);
  for (let i = 0; i < src.length; i++) {
    const j = s0 + i;
    if (j >= 0 && j < dst.length) dst[j] += src[i] * gain;
  }
}
