// Voices the script with Kokoro, an open-source text-to-speech model (Apache 2.0), running locally.
//
//   node scripts/voice.mjs [voice]   →   public/voice/*.wav + src/film/voice-manifest.json
//
// Every line is pinned to a moment in a section, measured once it's spoken, and checked against the
// cut: a line that overruns its section or runs into the next one is reported, not silently clipped.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { KokoroTTS } from "kokoro-js";

const timing = JSON.parse(readFileSync(new URL("../src/film/timing.json", import.meta.url)));
const script = JSON.parse(readFileSync(new URL("../src/film/voice.json", import.meta.url)));
const voice = process.argv[2] ?? script.voice;

// The same grid the film uses (src/film/grid.ts), reimplemented here so this runs under plain Node.
const BAR = timing.beat * 4;
const starts = {};
let total = 0;
for (const s of timing.sections) { starts[s.name] = { from: total, to: total + s.bars * BAR, factor: (timing.baseBeat / timing.beat) * s.speed }; total += s.bars * BAR; }
const frameOf = (section, at) => starts[section].from + Math.round(at / starts[section].factor);

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
  // Even out the level between lines, so none of them jumps out of the mix.
  const data = audio.audio;
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  if (peak > 0) for (let k = 0; k < data.length; k++) data[k] *= 0.9 / peak;
  const file = `voice/line-${i}.wav`;
  await audio.save(`public/${file}`);
  const seconds = data.length / audio.sampling_rate;
  lines.push({ file, text: line.text, section: line.section, from: frameOf(line.section, line.at), frames: Math.ceil(seconds * timing.fps), seconds });
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
  console.log(`${(l.from / timing.fps).toFixed(2).padStart(6)}s → ${(end / timing.fps).toFixed(2).padStart(6)}s  ${l.seconds.toFixed(2)}s  ${l.text}${issues.length ? "   ⚠ " + issues.join("; ") : ""}`);
}
writeFileSync(new URL("../src/film/voice-manifest.json", import.meta.url), JSON.stringify({ voice, lines: lines.map(({ file, from, frames }) => ({ file, from, frames })) }, null, 2) + "\n");
console.log(problems ? `\n${problems} timing problem(s)` : "\nevery line fits its moment");
