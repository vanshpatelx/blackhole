import React from "react";
import { useFilmFrame } from "./tempo";
import {interpolate} from "remotion";

export type Waypoint = { frame: number; x: number; y: number; click?: boolean };

const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/**
 * A pointer that moves like a hand: curved paths rather than straight lines, a small overshoot
 * that it corrects, a little drift while it rests, and a press that visibly squashes.
 */
export const Cursor: React.FC<{ path: Waypoint[]; scale?: number }> = ({ path, scale = 1 }) => {
  const frame = useFilmFrame();
  if (path.length === 0 || frame < path[0].frame - 1) return null;

  let x = path[path.length - 1].x;
  let y = path[path.length - 1].y;
  for (let i = 0; i < path.length - 1; i++) {
    const a = path[i], b = path[i + 1];
    if (frame >= a.frame && frame <= b.frame) {
      const t = easeInOut((frame - a.frame) / Math.max(1, b.frame - a.frame));
      // Bow the path to one side, the way a wrist arcs.
      const bow = Math.sin(t * Math.PI) * 0.12;
      const dx = b.x - a.x, dy = b.y - a.y;
      // Overshoot slightly past the target, then settle back over the last stretch.
      const over = t > 0.82 ? Math.sin(((t - 0.82) / 0.18) * Math.PI) * 0.025 : 0;
      x = a.x + dx * (t + over) - dy * bow;
      y = a.y + dy * (t + over) + dx * bow;
      break;
    }
    if (frame < path[0].frame) { x = path[0].x; y = path[0].y; }
  }
  // Resting drift.
  x += Math.sin(frame / 9) * 1.2;
  y += Math.cos(frame / 11) * 1.0;

  const press = path.some((p) => p.click && frame >= p.frame && frame < p.frame + 5);
  const fadeIn = interpolate(frame, [path[0].frame - 1, path[0].frame + 4], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <svg
      width={26 * scale}
      height={34 * scale}
      viewBox="0 0 26 34"
      style={{
        position: "absolute",
        left: x,
        top: y,
        opacity: fadeIn,
        transform: `scale(${press ? 0.86 : 1})`,
        transformOrigin: "0 0",
        filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.35))",
        zIndex: 50
      }}
    >
      <path d="M2 2 L2 27 L8.5 21 L13 31 L17 29.2 L12.6 19.6 L21.5 19.6 Z" fill="#fff" stroke="#111" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  );
};
