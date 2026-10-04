import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { font, space } from "./theme";

/** How much to scale the product mock so it reads at any aspect ratio. Designed at ~1150x420. */
export const useFit = () => {
  const { width, height } = useVideoConfig();
  return Math.min(width / 1150, (height * 0.6) / 420);
};

export const Ground: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: space, fontFamily: font, overflow: "hidden" }}>{children}</AbsoluteFill>
);

/** A line of copy that rises in. Sized off the frame width so it reads on a phone in any format. */
export const Caption: React.FC<{
  text: string;
  delay?: number;
  top?: number;
  size?: number;
  dim?: boolean;
}> = ({ text, delay = 0, top, size = 1, dim = false }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = spring({ frame: frame - delay, fps, config: { damping: 200, mass: 0.6 } });
  const base = Math.min(width * 0.046, height * 0.07) * size;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: top ?? height * 0.11,
        textAlign: "center",
        padding: `0 ${width * 0.06}px`,
        fontSize: base,
        fontWeight: 650,
        letterSpacing: "-0.025em",
        lineHeight: 1.12,
        // Narrow formats otherwise strand the last word on its own line.
        textWrap: "balance",
        color: dim ? "rgba(255,255,255,0.55)" : "#fff",
        opacity: t,
        transform: `translateY(${interpolate(t, [0, 1], [base * 0.5, 0])}px)`,
        fontFamily: font
      }}
    >
      {text}
    </div>
  );
};

/** Centres the product mock under the captions, scaled to fit. */
export const Product: React.FC<{ children: React.ReactNode; y?: number }> = ({ children, y = 0.6 }) => {
  const { height } = useVideoConfig();
  const fit = useFit();
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        top: height * y,
        transform: `translate(-50%, -50%) scale(${fit})`,
        transformOrigin: "center center"
      }}
    >
      {children}
    </div>
  );
};

/** The black menu-bar strip with a notch, standing in for the top of a MacBook display. */
export const MenuBar: React.FC<{ reveal?: number }> = ({ reveal = 1 }) => {
  const { width } = useVideoConfig();
  const fit = useFit();
  const barH = 38 * fit;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: interpolate(reveal, [0, 1], [-barH * 1.4, 0]),
        height: barH,
        background: "#000",
        boxShadow: "0 1px 0 rgba(255,255,255,0.06)"
      }}
    >
      <div
        style={{
          position: "absolute",
          left: width / 2 - 100 * fit,
          width: 200 * fit,
          top: 0,
          height: barH,
          background: "#000",
          borderBottomLeftRadius: 12 * fit,
          borderBottomRightRadius: 12 * fit
        }}
      />
      <div
        style={{
          position: "absolute",
          right: width * 0.03,
          top: 0,
          height: barH,
          display: "flex",
          alignItems: "center",
          gap: 14 * fit,
          color: "rgba(255,255,255,0.85)",
          fontSize: 12 * fit,
          fontFamily: font
        }}
      >
        <span>Fri 9:41 AM</span>
      </div>
    </div>
  );
};
