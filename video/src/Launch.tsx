import React from "react";
import { AbsoluteFill, Series, interpolate, useCurrentFrame } from "remotion";
import { Assistant, Command, End, Hook, Island, NotchReveal, Open, Tick } from "./scenes";

/** Seconds on screen for each beat. Kept short: the whole film has to work muted, on a phone, mid-scroll. */
const beats: Array<[React.FC, number]> = [
  [Hook, 3.2],
  [NotchReveal, 2.6],
  [Open, 4.2],
  [Tick, 3.4],
  [Island, 4.4],
  [Command, 5.4],
  [Assistant, 4.4],
  [End, 3.6]
];

const FADE = 8;

/** A short cross-fade in and out of every beat, so cuts feel like one continuous move. */
const Faded: React.FC<{ frames: number; children: React.ReactNode }> = ({ frames, children }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, FADE, frames - FADE, frames], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp"
  });
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

export const totalFrames = (fps: number) => beats.reduce((sum, [, s]) => sum + Math.round(s * fps), 0);

export const Launch: React.FC = () => (
  <AbsoluteFill style={{ background: "#0E1018" }}>
    <Series>
      {beats.map(([Scene, seconds], i) => {
        const frames = Math.round(seconds * 30);
        return (
          <Series.Sequence key={i} durationInFrames={frames}>
            <Faded frames={frames}>
              <Scene />
            </Faded>
          </Series.Sequence>
        );
      })}
    </Series>
  </AbsoluteFill>
);
