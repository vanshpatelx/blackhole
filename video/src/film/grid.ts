/** The film is cut to the soundtrack: 120 BPM at 30fps is 15 frames a beat and 60 a bar. */
export const BEAT = 15;
export const BAR = BEAT * 4;
export const at = (bar: number, beat = 0) => (bar - 1) * BAR + beat * BEAT;
export const FILM_FRAMES = at(17);
