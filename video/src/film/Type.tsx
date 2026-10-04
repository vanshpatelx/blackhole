import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { inkColor, sans, serif } from "./fonts";

export type Word = { text: string; at: number; serif?: boolean };

/**
 * A line that arrives word by word, each on its beat. Every word holds its place from the start,
 * invisible, so the line never reflows as it builds — the thing that gives cheap kinetic type away.
 */
export const Words: React.FC<{
  words: Word[];
  size?: number;
  y?: number;
  color?: string;
  out?: number;
}> = ({ words, size = 1, y = 0.5, color = inkColor, out }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const px = Math.min(width * 0.058, height * 0.1) * size;
  const leave = out === undefined ? 1 : interpolate(frame, [out, out + 6], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div
      style={{
        position: "absolute",
        left: width * 0.07,
        right: width * 0.07,
        top: y * height,
        transform: "translateY(-50%)",
        textAlign: "center",
        fontFamily: sans,
        fontSize: px,
        fontWeight: 600,
        letterSpacing: "-0.035em",
        lineHeight: 1.08,
        color,
        opacity: leave,
        textWrap: "balance"
      }}
    >
      {words.map((w, i) => {
        const t = interpolate(frame, [w.at, w.at + 7], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
        const e = 1 - Math.pow(1 - t, 3);
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              marginRight: "0.24em",
              opacity: e,
              filter: `blur(${(1 - e) * 10}px)`,
              transform: `translateY(${(1 - e) * 0.28}em)`,
              ...(w.serif ? { fontFamily: serif, fontStyle: "italic", fontWeight: 400, letterSpacing: "-0.01em", fontSize: "1.12em" } : {})
            }}
          >
            {w.text}
          </span>
        );
      })}
    </div>
  );
};
