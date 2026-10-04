import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig, Easing } from "remotion";
import { Caption, Ground, MenuBar, Product, useFit } from "./layout";
import { Card, Holey, Ring, TaskRow, clock } from "./ui";
import { font, palette } from "./theme";

const ease = Easing.bezier(0.22, 1, 0.36, 1);

/** The workspace as it drops out of the notch. `done` ticks the first task; `added` adds rows. */
const Workspace: React.FC<{
  open?: number;
  done?: number;
  extra?: string[];
  extraIn?: number;
  onlyExtra?: boolean;
}> = ({ open = 1, done = 0, extra = [], extraIn = 1, onlyExtra = false }) => (
  <div
    style={{
      width: 1054,
      background: palette.panel,
      borderRadius: "0 0 28px 28px",
      padding: "0 24px 10px",
      boxSizing: "border-box",
      transform: `scale(${interpolate(open, [0, 1], [0.94, 1])})`,
      transformOrigin: "top center",
      opacity: open,
      fontFamily: font
    }}
  >
    <div style={{ height: 44, display: "flex", alignItems: "center", gap: 10, color: "#fff" }}>
      <Holey size={24} />
      <span style={{ fontSize: 15, fontWeight: 600 }}>Black Hole</span>
      <span style={{ flex: 1 }} />
      {["Workspace", "Insights", "Settings"].map((t, i) => (
        <span
          key={t}
          style={{
            fontSize: 12.5,
            padding: "5px 11px",
            borderRadius: 8,
            background: i === 0 ? palette.chrome : "transparent",
            color: "rgba(255,255,255,0.88)"
          }}
        >
          {t}
        </span>
      ))}
    </div>
    <div style={{ display: "flex", gap: 8 }}>
      <Card tint={palette.tasks} width={300} title="Today's tasks" icon="☰">
        <div
          style={{
            background: palette.well,
            borderRadius: 12,
            padding: "9px 12px",
            fontSize: 13,
            color: palette.inkSecondary
          }}
        >
          ＋ What needs doing?
        </div>
        {onlyExtra ? null : (
          <>
            <TaskRow title="Ship the launch video" done={done} meta="45m" />
            <TaskRow title="Reply to Show HN" meta="Today 3:00 PM" />
          </>
        )}
        {extra.map((title, i) => (
          <div
            key={title}
            style={{
              opacity: interpolate(extraIn, [i * 0.25, i * 0.25 + 0.35], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp"
              }),
              transform: `translateX(${interpolate(extraIn, [i * 0.25, i * 0.25 + 0.35], [24, 0], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp"
              })}px)`
            }}
          >
            <TaskRow title={title} />
          </div>
        ))}
      </Card>
      <Card tint={palette.timer} width={172} title="" icon="">
        <div style={{ textAlign: "center", marginTop: 18 }}>
          <div style={{ fontSize: 42, fontWeight: 700, letterSpacing: "0.04em" }}>25:00</div>
          <div style={{ fontSize: 12, color: palette.inkSecondary }}>Ready</div>
          <div
            style={{
              margin: "34px auto 0",
              width: 92,
              padding: "8px 0",
              borderRadius: 10,
              background: palette.ink,
              color: "#fff",
              fontSize: 13,
              fontWeight: 600
            }}
          >
            ▶ Start
          </div>
        </div>
      </Card>
      <Card tint={palette.notepad} width={182} title="Notepad" icon="✎">
        <div style={{ fontSize: 13, lineHeight: 1.5 }}>
          Launch day
          <br />— record the video
          <br />— post on X
          <br />— thank everyone
        </div>
      </Card>
      <Card tint={palette.events} width={152} title="Events" icon="▦">
        <div style={{ background: palette.wellStrong, borderRadius: 11, padding: 9, fontSize: 12.5 }}>
          <b>Design review</b>
          <div style={{ fontSize: 11, color: palette.inkSecondary }}>Happening now</div>
        </div>
      </Card>
      <Card tint={palette.music} width={168} title="Playing" icon="♪">
        <div style={{ display: "flex", gap: 9 }}>
          <div style={{ width: 42, height: 42, borderRadius: 7, background: palette.wellStrong }} />
          <div style={{ fontSize: 12.5, fontWeight: 600 }}>
            Deep work
            <div style={{ fontSize: 11, fontWeight: 400, color: palette.inkSecondary }}>Focus mix</div>
          </div>
        </div>
      </Card>
    </div>
  </div>
);

// 1 — the problem, in the first two seconds, because that's all autoplay gives you.
export const Hook: React.FC = () => {
  const { height } = useVideoConfig();
  return (
    <Ground>
      <Caption text="Your to-do list is one window too far away." top={height * 0.36} size={1.2} />
      <Caption text="So you stop looking at it." delay={34} top={height * 0.52} size={1.2} dim />
    </Ground>
  );
};

// 2 — where it could live instead.
export const NotchReveal: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, height } = useVideoConfig();
  const bar = spring({ frame, fps, config: { damping: 200 } });
  const arrow = interpolate(frame, [20, 40], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Ground>
      <MenuBar reveal={bar} />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: height * 0.1,
          textAlign: "center",
          color: "#fff",
          fontSize: height * 0.07,
          opacity: arrow,
          transform: `translateY(${(1 - arrow) * -12}px)`
        }}
      >
        ↑
      </div>
      <Caption text="What if it lived right here?" delay={18} top={height * 0.32} size={1.15} />
    </Ground>
  );
};

// 3 — it drops out of the notch, the way hovering does.
export const Open: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const open = spring({ frame: frame - 6, fps, config: { damping: 18, mass: 0.9, stiffness: 120 } });
  return (
    <Ground>
      <MenuBar />
      <Product y={0.5}>
        <Workspace open={Math.min(1, open)} />
      </Product>
      <Caption text="Hover the notch. Your whole day drops out." delay={30} top={undefined} />
    </Ground>
  );
};

// 4 — doing the actual job: ticking something off.
export const Tick: React.FC = () => {
  const frame = useCurrentFrame();
  const done = interpolate(frame, [24, 42], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  return (
    <Ground>
      <MenuBar />
      <Product y={0.5}>
        <Workspace done={done} />
      </Product>
      <Caption text="Tasks, focus, notes and your calendar. One hover." delay={6} />
    </Ground>
  );
};

// 5 — the notch becomes the timer. Shown as a close-up: at true scale it's a sliver nobody notices.
export const Island: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const collapse = spring({ frame: frame - 6, fps, config: { damping: 200 } });
  const zoom = spring({ frame: frame - 14, fps, config: { damping: 22, mass: 0.9 } });
  // Time-lapsed — about a minute per second — so the ring visibly fills within the beat. At real
  // speed it moves a couple of percent and just reads as an empty circle.
  const seconds = 25 * 60 - (Math.max(0, frame - 24) / fps) * 55;
  const pillW = Math.min(width * 0.7, height * 1.15);
  const pillH = pillW * 0.13;
  return (
    <Ground>
      <MenuBar />
      <div style={{ opacity: 1 - collapse }}>
        <Product y={0.55}>
          <Workspace />
        </Product>
      </div>
      <div
        style={{
          position: "absolute",
          left: width / 2 - pillW / 2,
          top: height * 0.56 - pillH / 2,
          width: pillW,
          height: pillH,
          borderRadius: pillH * 0.42,
          background: "#000",
          boxShadow: "0 30px 80px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.05)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: `0 ${pillH * 0.42}px`,
          boxSizing: "border-box",
          opacity: zoom,
          transform: `scale(${interpolate(zoom, [0, 1], [0.6, 1])})`,
          fontFamily: font
        }}
      >
        <Ring progress={1 - seconds / (25 * 60)} size={pillH * 0.56} />
        {/* The camera, so the pill reads as the notch rather than a button. */}
        <div style={{ width: pillH * 0.16, height: pillH * 0.16, borderRadius: 999, background: "#1b1d26" }} />
        <span
          style={{
            color: palette.islandAccent,
            fontWeight: 650,
            fontSize: pillH * 0.42,
            fontVariantNumeric: "tabular-nums",
            letterSpacing: "0.01em"
          }}
        >
          {clock(seconds)}
        </span>
      </div>
      <Caption text="Start a focus session. The notch keeps time." delay={16} top={height * 0.2} />
    </Ground>
  );
};

// 6 — the command bar, at a size you can read on a phone.
export const Command: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, height, width } = useVideoConfig();
  const keys = spring({ frame, fps, config: { damping: 14 } });
  const bar = spring({ frame: frame - 20, fps, config: { damping: 200 } });
  const typed = "call mika tomorrow at 3pm";
  const chars = Math.floor(
    interpolate(frame, [32, 92], [0, typed.length], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })
  );
  const pill = interpolate(frame, [96, 110], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const barW = Math.min(width * 0.78, height * 1.25);
  const barH = barW * 0.11;
  const k = barH / 56;
  const keyStyle: React.CSSProperties = {
    padding: `${12 * k}px ${22 * k}px`,
    borderRadius: 12 * k,
    background: "linear-gradient(#3d3d44, #26262b)",
    color: "#fff",
    fontSize: 26 * k,
    fontWeight: 600,
    boxShadow: "0 4px 0 #111, 0 10px 28px rgba(0,0,0,0.4)",
    fontFamily: font
  };
  return (
    <Ground>
      <MenuBar />
      <div
        style={{
          position: "absolute",
          top: height * 0.66,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          gap: 14 * k,
          transform: `scale(${keys})`
        }}
      >
        <span style={keyStyle}>⌥</span>
        <span style={{ ...keyStyle, minWidth: 190 * k, textAlign: "center" }}>space</span>
      </div>
      <div
        style={{
          position: "absolute",
          top: height * 0.44 - barH / 2 + interpolate(bar, [0, 1], [-24, 0]),
          left: width / 2 - barW / 2,
          width: barW,
          height: barH,
          borderRadius: 16 * k,
          background: "#000",
          border: "1px solid rgba(255,255,255,0.09)",
          boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
          display: "flex",
          alignItems: "center",
          gap: 12 * k,
          padding: `0 ${18 * k}px`,
          boxSizing: "border-box",
          opacity: bar,
          fontFamily: font
        }}
      >
        <Holey size={24 * k} />
        <span style={{ color: "#fff", fontSize: 17 * k, fontWeight: 500, flex: 1, whiteSpace: "nowrap" }}>
          {typed.slice(0, chars)}
          <span style={{ opacity: frame % 30 < 15 ? 1 : 0, color: "#7aa7ff" }}>|</span>
        </span>
        <span
          style={{
            fontSize: 12.5 * k,
            color: "rgba(255,255,255,0.75)",
            padding: `${5 * k}px ${10 * k}px`,
            borderRadius: 999,
            background: "rgba(255,255,255,0.11)",
            opacity: pill,
            whiteSpace: "nowrap"
          }}
        >
          Tomorrow · 3:00 PM
        </span>
      </div>
      <Caption text="⌥Space from anywhere. Just type it." delay={8} top={height * 0.2} />
    </Ground>
  );
};

// 7 — an assistant doing the same job, through the MCP server.
export const Assistant: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, height, width } = useVideoConfig();
  const fit = useFit();
  const bubble = spring({ frame, fps, config: { damping: 200 } });
  const rows = interpolate(frame, [40, 90], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Ground>
      <MenuBar />
      <div
        style={{
          position: "absolute",
          top: height * 0.25,
          left: width / 2 - 300 * fit,
          width: 600 * fit,
          opacity: bubble,
          transform: `translateY(${(1 - bubble) * 20}px)`,
          fontFamily: font
        }}
      >
        <div style={{ fontSize: 12 * fit, color: "rgba(255,255,255,0.55)", marginBottom: 6 * fit }}>
          You, in your AI assistant
        </div>
        <div
          style={{
            background: "rgba(255,255,255,0.1)",
            color: "#fff",
            borderRadius: 18 * fit,
            padding: `${14 * fit}px ${18 * fit}px`,
            fontSize: 17 * fit
          }}
        >
          Add my three most urgent issues to today.
        </div>
      </div>
      <Product y={0.68}>
        <Workspace
          onlyExtra
          extra={["Fix login redirect", "Bump the DMG version", "Answer the security report"]}
          extraIn={rows}
        />
      </Product>
      <Caption text="Or let Claude and ChatGPT run your day." delay={50} top={height * 0.06} />
    </Ground>
  );
};

// 8 — what it is, and where to get it.
export const End: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, height } = useVideoConfig();
  const logo = spring({ frame, fps, config: { damping: 12, mass: 0.8 } });
  const base = height * 0.075;
  return (
    <Ground>
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: base * 0.35,
          fontFamily: font
        }}
      >
        <div style={{ transform: `scale(${logo})` }}>
          <Holey size={base * 2.2} />
        </div>
        <div style={{ color: "#fff", fontSize: base * 1.1, fontWeight: 700, letterSpacing: "-0.03em" }}>
          Black Hole
        </div>
        <div style={{ color: "rgba(255,255,255,0.6)", fontSize: base * 0.42 }}>
          Free and open source · for Mac
        </div>
        <div
          style={{
            marginTop: base * 0.25,
            color: "#fff",
            fontSize: base * 0.46,
            fontWeight: 600,
            padding: `${base * 0.18}px ${base * 0.5}px`,
            borderRadius: 999,
            background: "rgba(255,255,255,0.12)",
            opacity: interpolate(frame, [20, 34], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })
          }}
        >
          getblackhole.app
        </div>
      </div>
    </Ground>
  );
};
