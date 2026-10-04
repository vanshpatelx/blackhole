import timing from "./timing.json";

/**
 * The film is cut to the soundtrack, and both read their timing from timing.json so they cannot
 * drift apart. A beat is a whole number of frames so cuts land exactly: 13 frames at 30fps is
 * 138.46 BPM.
 */
export const FPS = timing.fps;
export const BEAT = timing.beat;
export const BAR = BEAT * 4;
export const BPM = (60 * FPS) / BEAT;

export type Section = "hook" | "build" | "workday" | "keeps" | "command" | "ask" | "montage" | "end";
const list = timing.sections as Array<{ name: Section; bars: number; speed: number }>;
const find = (s: Section) => list.find((x) => x.name === s)!;

/** First frame of a section. */
export const startOf = (s: Section) => list.slice(0, list.findIndex((x) => x.name === s)).reduce((f, x) => f + x.bars * BAR, 0);
export const lengthOf = (s: Section) => find(s).bars * BAR;
/**
 * Animations inside a section were written against a 15-frame beat; this is how many of those
 * frames pass per frame of film. `speed` above 1 tightens a section without re-timing its moves.
 */
export const factorOf = (s: Section) => (timing.baseBeat / BEAT) * find(s).speed;
/** Where a moment written in a section's original frames lands in the film. */
export const cue = (s: Section, original: number) => startOf(s) + Math.round(original / factorOf(s));
export const FILM_FRAMES = list.reduce((f, x) => f + x.bars * BAR, 0);
