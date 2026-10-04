import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { loadFont as loadSerif } from "@remotion/google-fonts/InstrumentSerif";

// Inter carries the film; Instrument Serif is kept for one or two words, where a voice would lean in.
export const sans = loadInter("normal", { weights: ["400", "500", "600", "700"], subsets: ["latin"] }).fontFamily;
export const serif = loadSerif("italic", { subsets: ["latin"] }).fontFamily;

export const paper = "#F4F1EC";
export const inkColor = "#16161A";
