import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";

/**
 * Film grain that changes every other frame. Perfectly clean gradients are one of the things that
 * make motion graphics read as machine-made; a little texture fixes most of that.
 */
export const Grain: React.FC<{ opacity?: number }> = ({ opacity = 0.06 }) => {
  const seed = Math.floor(useCurrentFrame() / 2);
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "multiply", opacity }}>
      <svg width="100%" height="100%">
        <filter id={`g${seed}`}>
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed={seed} stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter={`url(#g${seed})`} />
      </svg>
    </AbsoluteFill>
  );
};
