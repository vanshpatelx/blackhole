import React from "react";
import { Img, staticFile } from "remotion";
import { font, palette } from "./theme";

/** One of the app's pastel cards. Same radius, tint and ink as the real thing. */
export const Card: React.FC<{
  tint: string;
  width: number;
  title: string;
  icon: string;
  children?: React.ReactNode;
}> = ({ tint, width, title, icon, children }) => (
  <div
    style={{
      width,
      height: 266,
      borderRadius: 18,
      background: tint,
      padding: 14,
      boxSizing: "border-box",
      color: palette.ink,
      fontFamily: font,
      display: "flex",
      flexDirection: "column",
      gap: 10,
      flexShrink: 0
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 13.5, fontWeight: 600 }}>
      <span style={{ fontSize: 12.5 }}>{icon}</span>
      {title}
    </div>
    {children}
  </div>
);

/** A task row: circle, title, optional strike-through when done. */
export const TaskRow: React.FC<{ title: string; done?: number; meta?: string }> = ({
  title,
  done = 0,
  meta
}) => (
  <div style={{ display: "flex", flexDirection: "column", gap: 3, padding: "6px 2px" }}>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div
        style={{
          width: 18,
          height: 18,
          borderRadius: 9,
          border: `1.6px solid ${palette.ink}`,
          background: done > 0.5 ? palette.ink : "transparent",
          color: palette.tasks,
          fontSize: 11,
          fontWeight: 800,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transform: `scale(${1 + Math.sin(done * Math.PI) * 0.25})`
        }}
      >
        {done > 0.5 ? "✓" : ""}
      </div>
      <div style={{ fontSize: 13.5, position: "relative", opacity: 1 - done * 0.4 }}>
        {title}
        <div
          style={{
            position: "absolute",
            left: 0,
            top: "52%",
            height: 1.5,
            width: `${done * 100}%`,
            background: palette.ink
          }}
        />
      </div>
    </div>
    {meta ? (
      <div style={{ fontSize: 11.5, color: palette.inkSecondary, paddingLeft: 28 }}>{meta}</div>
    ) : null}
  </div>
);

/** Holey, the app's own mascot — drawn from the app icon, not anyone else's character. */
export const Holey: React.FC<{ size: number; bounce?: number }> = ({ size, bounce = 0 }) => (
  <Img
    src={staticFile("icon.png")}
    style={{
      width: size,
      height: size,
      transform: `translateY(${-bounce * size * 0.18}px) scale(${1 + bounce * 0.12})`
    }}
  />
);

/** The live island ring: gradient arc showing how much of the session is done. */
export const Ring: React.FC<{ progress: number; size: number }> = ({ progress, size }) => {
  const r = size / 2 - 2;
  const c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
      <defs>
        <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FFB36B" />
          <stop offset="0.35" stopColor="#FF5E7E" />
          <stop offset="0.7" stopColor="#A77BF3" />
          <stop offset="1" stopColor="#62B6FF" />
        </linearGradient>
      </defs>
      <circle cx={size / 2} cy={size / 2} r={r} stroke="rgba(255,255,255,0.16)" strokeWidth={3} fill="none" />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        stroke="url(#ring)"
        strokeWidth={3}
        fill="none"
        strokeLinecap="round"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - progress)}
      />
    </svg>
  );
};

export const clock = (seconds: number) => {
  const s = Math.max(0, Math.round(seconds));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
};
