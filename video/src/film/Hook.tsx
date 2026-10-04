import React from "react";
import { AbsoluteFill, interpolate, spring, useVideoConfig } from "remotion";
import { inkColor, paper, sans, serif } from "./fonts";
import { useFilmFrame } from "./tempo";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/**
 * The opening: a day scattered across a dozen places, then the notch tearing open into a black
 * hole that pulls all of it in. Bar one is the chaos, bar two is the pull. The first frame is
 * already full, so it works as a thumbnail and nobody watches a blank fade.
 */

type Bit = { x: number; y: number; rot: number; at: number; bg: string; ink?: string; body: React.ReactNode; wide?: boolean };

// Everything a working day leaves lying around. Generic on purpose: no apps, no logos.
const bits: Bit[] = [
  { x: 0.14, y: 0.22, rot: -8, at: -20, bg: "#F2D675", body: <b>call mika!!</b> },
  { x: 0.8, y: 0.15, rot: 3, at: -20, bg: "#FFFFFF", wide: true, body: <><span style={{ color: "#FF5E7E" }}>●</span> Standup in 5 min</> },
  { x: 0.83, y: 0.62, rot: -4, at: -20, bg: "#9DB8A2", body: <>☐ reply to Show HN<br />☐ ship the DMG</> },
  { x: 0.2, y: 0.7, rot: 6, at: -20, bg: "#A79DC4", body: <b style={{ fontSize: "1.6em", letterSpacing: "0.02em" }}>25:00</b> },
  { x: 0.6, y: 0.86, rot: -3, at: -20, bg: "#97AEC4", wide: true, body: <><b>Design review</b> · 11:00</> },
  { x: 0.08, y: 0.37, rot: 4, at: -20, bg: "#FFFFFF", body: <>💬 3 unread messages</> },
  { x: 0.45, y: 0.11, rot: -2, at: -20, bg: "#FFFFFF", wide: true, body: <>Mail · Docs · Sheets · Notes · <b>+12</b></> },
  { x: 0.91, y: 0.39, rot: -6, at: 4, bg: "#E9B8C6", body: <>⏰ invoice due today</> },
  { x: 0.38, y: 0.8, rot: 5, at: 11, bg: "#C9A39E", body: <>♪ Slow mornings</> },
  { x: 0.66, y: 0.27, rot: 7, at: 18, bg: "#F4B783", body: <b>buy milk</b> },
  { x: 0.3, y: 0.3, rot: -5, at: 26, bg: "#FFFFFF", wide: true, body: <>You have <b>47 tabs</b> open</> },
  { x: 0.79, y: 0.85, rot: 5, at: 33, bg: "#FBF6EC", body: <>ideas.txt — launch plan…</> },
  { x: 0.06, y: 0.83, rot: -7, at: 41, bg: "#9DB8A2", body: <>☐ ☐ ☐</> },
  { x: 0.95, y: 0.81, rot: 9, at: 48, bg: "#16161A", ink: "#FFFFFF", body: <>Focus? ✕</> }
];

const PULL = 62; // where bar two starts pulling, in the section's original frames
const pullStart = (i: number) => PULL + 4 + i * 2.5;

export const Hook: React.FC = () => {
  const frame = useFilmFrame();
  const { width: W, height: H, fps } = useVideoConfig();
  const u = Math.min(W, H * 1.6) / 1000;

  // The hole: opens out of the notch, drops into the frame to swallow everything, then folds back up.
  const open = spring({ frame: frame - PULL, fps, config: { damping: 18, mass: 0.9 } });
  const close = interpolate(frame, [106, 118], [0, 1], { ...clamp, easing: (t) => t * t });
  const radius = Math.min(W, H) * 0.13 * open * (1 - close);
  const cx = W / 2;
  const cy = interpolate(open, [0, 1], [H * 0.03, H * 0.24]) * (1 - close) + H * 0.03 * close;
  const spin = frame * 14;

  // Gravity: the screen shakes harder the more it swallows, and leans in.
  const shakeAmp = interpolate(frame, [64, 88, 112, 118], [0, 7, 9, 0], clamp) * u;
  const shakeX = (Math.sin(frame * 2.3) + Math.sin(frame * 3.7) * 0.6) * shakeAmp;
  const shakeY = (Math.cos(frame * 2.9) + Math.sin(frame * 1.9) * 0.6) * shakeAmp;
  const lean = interpolate(frame, [PULL, 116], [1, 1.07], clamp);

  /**
   * Where a thing is, given when it started falling in: a tightening, accelerating spiral around
   * wherever the hole is at this moment. Before it starts falling, that is exactly where it was put.
   */
  const fall = (x0: number, y0: number, start: number) => {
    const p = interpolate(frame, [start, start + 22], [0, 1], clamp);
    const e = p * p;
    if (e === 0) return { x: x0, y: y0, p, e };
    const dx = x0 - cx, dy = y0 - cy;
    const r = Math.hypot(dx, dy) * (1 - e), a = Math.atan2(dy, dx) + e * Math.PI * 2.2;
    return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a), p, e };
  };

  // The headline arrives on the beat, and goes in last.
  const words: Array<{ text: string; at: number; serif?: boolean }> = [
    { text: "Your", at: -6 }, { text: "day", at: 6 }, { text: "is", at: 12 }, { text: "everywhere.", at: 20, serif: true }
  ];
  const headline = fall(W / 2, H * 0.5, 100);

  return (
    <AbsoluteFill style={{ background: paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `translate(${shakeX}px, ${shakeY}px) scale(${lean})`, transformOrigin: `${cx}px ${cy}px` }}>
        {/* A shadow pooling around the hole as it opens. */}
        <div
          style={{
            position: "absolute",
            left: cx - radius * 5,
            top: cy - radius * 5,
            width: radius * 10,
            height: radius * 10,
            borderRadius: "50%",
            background: "radial-gradient(circle, rgba(22,22,26,0.28) 0%, rgba(22,22,26,0) 60%)"
          }}
        />

        {bits.map((b, i) => {
          const pop = spring({ frame: frame - b.at, fps, config: { damping: 10, mass: 0.6, stiffness: 180 } });
          if (frame < b.at) return null;
          const wobbleX = Math.sin(frame / 6 + i) * 3 * u, wobbleY = Math.cos(frame / 7 + i * 2) * 3 * u;
          const f = fall(b.x * W, b.y * H, pullStart(i));
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left: f.x + (1 - f.e) * wobbleX,
                top: f.y + (1 - f.e) * wobbleY,
                transform: `translate(-50%, -50%) rotate(${b.rot + f.e * 540}deg) scale(${Math.max(0, pop * (1 - f.e))})`,
                opacity: 1 - interpolate(f.p, [0.85, 1], [0, 1], clamp),
                filter: `blur(${f.e * 6}px)`,
                background: b.bg,
                color: b.ink ?? inkColor,
                fontFamily: sans,
                fontSize: 19 * u,
                lineHeight: 1.35,
                padding: `${12 * u}px ${16 * u}px`,
                borderRadius: 14 * u,
                whiteSpace: "nowrap",
                boxShadow: `0 ${10 * u}px ${28 * u}px rgba(40,30,20,0.18), 0 0 0 1px rgba(0,0,0,0.04)`
              }}
            >
              {b.body}
            </div>
          );
        })}

        {/* The hole: a ring of the app's own colours spinning around a core of black. */}
        {radius > 0.5 ? (
          <>
            <div
              style={{
                position: "absolute",
                left: cx - radius * 2.3,
                top: cy - radius * 2.3,
                width: radius * 4.6,
                height: radius * 4.6,
                borderRadius: "50%",
                background: `conic-gradient(from ${spin}deg, #FFB36B, #FF5E7E, #A77BF3, #62B6FF, #FFB36B)`,
                WebkitMaskImage: "radial-gradient(circle, transparent 38%, black 46%, black 52%, transparent 70%)",
                maskImage: "radial-gradient(circle, transparent 38%, black 46%, black 52%, transparent 70%)",
                filter: `blur(${2 * u}px)`,
                opacity: 0.95
              }}
            />
            <div
              style={{
                position: "absolute",
                left: cx - radius,
                top: cy - radius,
                width: radius * 2,
                height: radius * 2,
                borderRadius: "50%",
                background: "#000",
                boxShadow: `0 0 ${radius * 0.6}px ${radius * 0.25}px #000`
              }}
            />
          </>
        ) : null}

        {/* The headline, on a soft pool of paper so it reads over the clutter. */}
        <div
          style={{
            position: "absolute",
            left: headline.x,
            top: headline.y,
            transform: `translate(-50%, -50%) scale(${1 - headline.e}) rotate(${headline.e * 320}deg)`,
            opacity: 1 - interpolate(headline.p, [0.85, 1], [0, 1], clamp),
            filter: `blur(${headline.e * 6}px)`,
            whiteSpace: "nowrap",
            fontFamily: sans,
            fontWeight: 700,
            fontSize: Math.min(W * 0.085, H * 0.15),
            letterSpacing: "-0.045em",
            color: inkColor,
            textShadow: `0 0 ${40 * u}px ${paper}, 0 0 ${20 * u}px ${paper}, 0 0 ${8 * u}px ${paper}`
          }}
        >
          {words.map((w, i) => {
            const t = interpolate(frame, [w.at, w.at + 5], [0, 1], clamp);
            const e = 1 - Math.pow(1 - t, 3);
            return (
              <span
                key={i}
                style={{
                  display: "inline-block",
                  marginRight: "0.22em",
                  opacity: e,
                  transform: `translateY(${(1 - e) * 0.35}em) scale(${0.85 + 0.15 * e})`,
                  ...(w.serif ? { fontFamily: serif, fontStyle: "italic", fontWeight: 400, letterSpacing: "-0.01em", fontSize: "1.15em" } : {})
                }}
              >
                {w.text}
              </span>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
