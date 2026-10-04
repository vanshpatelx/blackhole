// Listens to the mix the way a meter would: loudness over time, tonal balance per section, whether
// the voice is clear in the band speech actually lives in, and whether any effect spikes over it.
//
//   node scripts/analyze.mjs     (after npm run mix)
import { readFileSync } from "node:fs";
import { SR, biquad, readWav, readWavStereo, rmsDb } from "./lib/dsp.mjs";

const timing = JSON.parse(readFileSync(new URL("../src/film/timing.json", import.meta.url)));
const manifest = JSON.parse(readFileSync(new URL("../src/film/voice-manifest.json", import.meta.url)));
const load = (p) => readWav(p).data;
const stems = { music: load("out/stems/music.wav"), voice: load("out/stems/voice.wav"), sfx: load("out/stems/sfx.wav"), amb: load("out/stems/ambience.wav") };
const n = Math.min(...Object.values(stems).map((s) => s.length));
const mix = new Float32Array(n), bg = new Float32Array(n);
for (let i = 0; i < n; i++) { bg[i] = stems.music[i] + stems.sfx[i] + stems.amb[i]; mix[i] = bg[i] + stems.voice[i]; }

const BAR = (timing.beat * 4) / timing.fps;
const sections = [];
let t = 0;
for (const s of timing.sections) { sections.push({ name: s.name, a: t, z: t + s.bars * BAR }); t += s.bars * BAR; }
const sectionAt = (sec) => sections.find((s) => sec >= s.a && sec < s.z)?.name ?? "tail";
const band = (d, lo, hi) => { const c = Float32Array.from(d); if (lo) biquad(c, "highpass", lo, 0.707); if (hi) biquad(c, "lowpass", hi, 0.707); if (lo) biquad(c, "highpass", lo, 0.707); if (hi) biquad(c, "lowpass", hi, 0.707); return c; };
const kWeight = (d) => { const c = Float32Array.from(d); biquad(c, "highshelf", 1681, 0.707, 4); biquad(c, "highpass", 38, 0.5); return c; };

// 1. Short-term loudness (3s, K-weighted), every half second.
console.log("1. LOUDNESS OVER TIME  (short-term, K-weighted; relative to the film's average)\n");
const k = kWeight(mix);
const avg = rmsDb(k);
for (let s = 0; s + 0.5 <= n / SR; s += 1.0) {
  const a = Math.floor(Math.max(0, s - 1.5) * SR), z = Math.floor(Math.min(n / SR, s + 1.5) * SR);
  const rel = rmsDb(k, a, z) - avg;
  console.log(`  ${s.toFixed(1).padStart(5)}s ${sectionAt(s).padEnd(8)} ${rel >= 0 ? "+" : ""}${rel.toFixed(1).padStart(5)} dB  ${"█".repeat(Math.max(0, Math.round(rel + 12)))}`);
}

// 2. Tonal balance per section.
const bands = [["sub <60", 0, 60], ["low 60-250", 60, 250], ["lowmid 250-500", 250, 500], ["mid 500-2k", 500, 2000], ["presence 2-5k", 2000, 5000], ["air 5k+", 5000, 0]];
const split = Object.fromEntries(bands.map(([name, lo, hi]) => [name, band(mix, lo, hi)]));
console.log("\n2. TONAL BALANCE  (each band relative to the section's total)\n");
console.log("  section   " + bands.map(([b]) => b.padStart(15)).join(""));
for (const s of sections) {
  const a = Math.floor(s.a * SR), z = Math.floor(Math.min(s.z, n / SR) * SR);
  const total = rmsDb(mix, a, z);
  console.log("  " + s.name.padEnd(9) + bands.map(([b]) => (rmsDb(split[b], a, z) - total).toFixed(1).padStart(15)).join(""));
}

// 3. Voice clarity where speech lives.
console.log("\n3. VOICE CLARITY  (voice over everything else: broadband, and in 1-4 kHz where words are understood)\n");
const vBand = band(stems.voice, 1000, 4000), bBand = band(bg, 1000, 4000);
for (const l of manifest.lines) {
  const a = Math.floor((l.from / timing.fps) * SR), z = Math.min(n, a + Math.floor((l.frames / timing.fps) * SR));
  const broad = rmsDb(stems.voice, a, z) - rmsDb(bg, a, z);
  const speech = rmsDb(vBand, a, z) - rmsDb(bBand, a, z);
  console.log(`  ${(l.from / timing.fps).toFixed(2).padStart(6)}s  broadband +${broad.toFixed(1)} dB   speech band ${speech >= 0 ? "+" : ""}${speech.toFixed(1)} dB${speech < 12 ? "   ⚠ masked in the speech band" : ""}`);
}

// 4. Effects that spike over the voice.
console.log("\n4. EFFECT SPIKES  (10 ms peaks of the effects against the voice's typical peak)\n");
const peakEnv = (d) => { const w = Math.floor(0.01 * SR), out = []; for (let i = 0; i + w <= d.length; i += w) { let m = 0; for (let j = i; j < i + w; j++) m = Math.max(m, Math.abs(d[j])); out.push(m); } return out; };
const vp = peakEnv(stems.voice).filter((v) => v > 1e-4).sort((x, y) => x - y);
const voiceTypical = vp[Math.floor(vp.length * 0.9)];
const sp = peakEnv(stems.sfx);
const spikes = [];
sp.forEach((v, i) => { const rel = 20 * Math.log10(v / voiceTypical); if (rel > -3) spikes.push([i * 0.01, rel]); });
const grouped = [];
for (const [ts, rel] of spikes) { const last = grouped[grouped.length - 1]; if (last && ts - last[0] < 0.25) last[1] = Math.max(last[1], rel); else grouped.push([ts, rel]); }
if (!grouped.length) console.log("  none within 3 dB of the voice's peaks");
for (const [ts, rel] of grouped) console.log(`  ${ts.toFixed(2).padStart(6)}s ${sectionAt(ts).padEnd(8)} ${rel >= 0 ? "+" : ""}${rel.toFixed(1)} dB against the voice's typical peak`);

// 5. Low end and image.
const subShare = 10 * Math.log10(split["sub <60"].reduce((s, v) => s + v * v, 0) / mix.reduce((s, v) => s + v * v, 0));
console.log(`\n5. LOW END AND IMAGE\n\n  energy below 60 Hz: ${subShare.toFixed(1)} dB of the total (phone speakers reproduce almost none of it)`);
// Width, and whether it survives being folded to one speaker.
const stereo = ["music", "sfx", "ambience"].map((name) => [name, readWavStereo(`out/stems/${name}.wav`)]);
let mid = 0, side = 0, lr = 0, mono = 0;
const v = stems.voice;
const len = Math.min(v.length, ...stereo.map(([, s]) => s.L.length));
for (let i = 0; i < len; i++) {
  let L = v[i], R = v[i];
  for (const [, s] of stereo) { L += s.L[i]; R += s.R[i]; }
  mid += ((L + R) / 2) ** 2; side += ((L - R) / 2) ** 2; lr += (L * L + R * R) / 2; mono += ((L + R) / 2) ** 2;
}
console.log(`  width (side vs mid): ${(10 * Math.log10(side / mid)).toFixed(1)} dB   (0 = fully wide; below -20 is close to mono)`);
console.log(`  folded to one speaker: ${(10 * Math.log10(mono / lr)).toFixed(1)} dB vs stereo   (near 0 means nothing cancels)`);
