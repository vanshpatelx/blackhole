import React from "react";
import { useVideoConfig } from "remotion";
import { sans } from "./fonts";

/** A 14-inch MacBook's logical screen, so the notch and the panel sit at their true proportions. */
export const SW = 1512;
export const SH = 982;
export const NOTCH_W = 196;
export const NOTCH_H = 37;
const BEZEL = 14;

/** An original wallpaper: soft warm light, nothing borrowed. */
const wallpaper = [
  "radial-gradient(55% 60% at 18% 30%, #F6C7A6 0%, rgba(246,199,166,0) 70%)",
  "radial-gradient(50% 55% at 78% 22%, #CEC5F3 0%, rgba(206,197,243,0) 70%)",
  "radial-gradient(60% 55% at 62% 88%, #BCDDF2 0%, rgba(188,221,242,0) 70%)",
  "radial-gradient(45% 45% at 12% 90%, #F3CFDC 0%, rgba(243,207,220,0) 70%)",
  "#F1E6DD"
].join(",");

/** The screen, with the notch and menu bar, and whatever is drawn on it in screen coordinates. */
export const MacScreen: React.FC<{ children?: React.ReactNode; dim?: number }> = ({ children, dim = 0 }) => (
  <div
    style={{
      width: SW + BEZEL * 2,
      height: SH + BEZEL * 2,
      borderRadius: 34,
      background: "#0B0B0D",
      padding: BEZEL,
      boxSizing: "border-box",
      boxShadow: "0 50px 120px rgba(40,30,20,0.28), 0 0 0 1.5px #2a2a2e"
    }}
  >
    <div style={{ position: "relative", width: SW, height: SH, borderRadius: 18, overflow: "hidden", background: wallpaper }}>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 0,
          height: NOTCH_H,
          background: "rgba(255,255,255,0.38)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 22px",
          fontFamily: sans,
          fontSize: 14,
          color: "rgba(20,20,24,0.86)"
        }}
      >
        <div style={{ display: "flex", gap: 22 }}>
          <b style={{ fontWeight: 650 }}>Notes</b>
          <span>File</span>
          <span>Edit</span>
          <span>View</span>
          <span>Window</span>
        </div>
        <div style={{ display: "flex", gap: 18 }}>
          <span>94%</span>
          <span>Fri 9:41 AM</span>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: SW / 2 - NOTCH_W / 2,
          top: 0,
          width: NOTCH_W,
          height: NOTCH_H,
          background: "#000",
          borderRadius: "0 0 12px 12px"
        }}
      />
      {children}
      {dim > 0 ? <div style={{ position: "absolute", inset: 0, background: `rgba(244,241,236,${dim})` }} /> : null}
    </div>
  </div>
);

/** How big the screen is drawn: whole screen in 16:9; cropped into the top in narrower formats. */
export const useScreenScale = () => {
  const { width, height } = useVideoConfig();
  if (width / height >= 1.5) return Math.min((width * 0.9) / (SW + BEZEL * 2), (height * 0.9) / (SH + BEZEL * 2));
  // Narrow formats: the panel is what matters, so frame it to fill the width.
  return (width * 0.94) / 1064;
};

/**
 * Frames the screen. With no target it shows the whole screen (16:9) or the top of it (narrower
 * formats). Given a target point in screen coordinates, it puts that point at (`placeX`, `placeY`)
 * in the frame — so pushing into the notch, or onto one card, is a matter of zoom and target.
 */
export const Camera: React.FC<{
  zoom?: number;
  x?: number;
  y?: number;
  placeX?: number;
  placeY?: number;
  children: React.ReactNode;
}> = ({ zoom = 1, x = SW / 2, y = 0, placeX = 0.5, placeY, children }) => {
  const { width, height } = useVideoConfig();
  const base = useScreenScale();
  const s = base * zoom;
  const py = placeY ?? wideFocus(width, height, base);
  return (
    <div
      style={{
        position: "absolute",
        left: placeX * width - (x + BEZEL) * s,
        top: py * height - (y + BEZEL) * s,
        transform: `scale(${s})`,
        transformOrigin: "0 0"
      }}
    >
      {children}
    </div>
  );
};

export const wideFocus = (width: number, height: number, base: number) =>
  width / height >= 1.5 ? (height - (SH + BEZEL * 2) * base) / 2 / height + (BEZEL * base) / height : 0.06;
