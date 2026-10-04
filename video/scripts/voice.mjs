// Voices the script with Kokoro, an open-source text-to-speech model (Apache 2.0), running locally.
//
//   node scripts/voice.mjs [voice]   →   public/voice/*.wav + src/film/voice-manifest.json
//
// Every line is pinned to a moment in a section, measured once it's spoken, and checked against the
// cut: a line that overruns its section or runs into the next one is reported, not silently clipped.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { KokoroTTS } from "kokoro-js";
import { readWav } from "./lib/dsp.mjs";

const timing = JSON.parse(readFileSync(new URL("../src/film/timing.json", import.meta.url)));
const script = JSON.parse(readFileSync(new URL("../src/film/voice.json", import.meta.url)));
const voice = process.argv[2] ?? script.voice;

// The same grid the film uses (src/film/grid.ts), reimplemented here so this runs under plain Node.
const BAR = timing.beat * 4;
const starts = {};
let total = 0;
for (const s of timing.sections) { starts[s.name] = { from: total, to: total + s.bars * BAR, factor: (timing.baseBeat / timing.beat) * s.speed }; total += s.bars * BAR; }
const frameOf = (section, at) => starts[section].from + Math.round(at / starts[section].factor);

// The music bed, to work out how far it has to come down under each line. It's stereo, so read it
// properly and fold it to mono for measuring — reading it as mono would double every time window.
const music = (() => { const w = readWav(new URL("../public/audio/music.wav", import.meta.url).pathname); return { sr: w.sr, d: w.data }; })();
const rmsDb = (d, a = 0, z = d.length) => {
  let s = 0;
  for (let i = a; i < z; i++) s += d[i] * d[i];
  return 20 * Math.log10(Math.sqrt(s / Math.max(1, z - a)) + 1e-9);
};
const { mix } = script;

const tts = await KokoroTTS.from_pretrained(script.model, { dtype: "q8", device: "cpu" });
mkdirSync("public/voice", { recursive: true });

const lines = [];
for (const [i, line] of script.lines.entries()) {
  const audio = await tts.generate(line.text, { voice, speed: script.speed });
  // Kokoro pads each clip with silence; trim it so a line's length is its speech, not its padding.
  const raw = audio.audio;
  const pad = Math.floor(0.03 * audio.sampling_rate);
  let first = 0, last = raw.length - 1;
  while (first < raw.length && Math.abs(raw[first]) < 0.01) first++;
  while (last > first && Math.abs(raw[last]) < 0.01) last--;
  audio.audio = raw.slice(Math.max(0, first - pad), Math.min(raw.length, last + pad));
  // Even out how loud the lines *sound*, not their peaks: peak-matching left some lines several dB
  // quieter than others. A ceiling keeps the loudest moments from clipping.
  const data = audio.audio;
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  const gain = Math.min(Math.pow(10, (mix.voiceRms - rmsDb(data)) / 20), 0.97 / Math.max(peak, 1e-6));
  for (let k = 0; k < data.length; k++) data[k] *= gain;
  const file = `voice/line-${i}.wav`;
  await audio.save(`public/${file}`);
  const seconds = data.length / audio.sampling_rate;
  const from = frameOf(line.section, line.at);
  // Bring the music down exactly as far as this line needs: hardly at all in the quiet opening,
  // a long way under the full groove.
  const a = Math.floor((from / timing.fps) * music.sr);
  const z = Math.min(music.d.length, a + Math.floor(seconds * music.sr));
  const bed = rmsDb(music.d, a, z) + 20 * Math.log10(mix.music);
  const needed = Math.pow(10, (rmsDb(data) - mix.clearance - bed) / 20);
  const duck = Math.max(mix.minDuck, Math.min(1, needed));
  const clear = rmsDb(data) - (bed + 20 * Math.log10(duck));
  lines.push({ file, text: line.text, section: line.section, from, frames: Math.ceil(seconds * timing.fps), seconds, duck, clear });
}

// Check the cut, not just the files.
let problems = 0;
console.log(`voice ${voice} at speed ${script.speed}\n`);
for (const [i, l] of lines.entries()) {
  const end = l.from + l.frames;
  const next = lines[i + 1];
  const issues = [];
  if (end > total) issues.push("runs past the end of the film");
  if (next && end > next.from) issues.push(`overlaps the next line by ${end - next.from} frames`);
  const section = starts[l.section];
  if (end > section.to + 8) issues.push(`spills ${end - section.to} frames past its section`);
  problems += issues.length;
  if (l.clear < mix.clearance - 0.5) issues.push(`only ${l.clear.toFixed(1)} dB over the music`);
  console.log(`${(l.from / timing.fps).toFixed(2).padStart(6)}s → ${(end / timing.fps).toFixed(2).padStart(6)}s  ${l.seconds.toFixed(2)}s  music ×${l.duck.toFixed(2)}  voice +${l.clear.toFixed(1)} dB  ${l.text}${issues.length ? "   ⚠ " + issues.join("; ") : ""}`);
}
writeFileSync(new URL("../src/film/voice-manifest.json", import.meta.url), JSON.stringify({ voice, lines: lines.map(({ file, from, frames, duck }) => ({ file, from, frames, duck: Number(duck.toFixed(3)) })) }, null, 2) + "\n");
console.log(problems ? `\n${problems} timing problem(s)` : "\nevery line fits its moment");
