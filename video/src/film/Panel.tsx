import React from "react";
import { interpolate } from "remotion";
import { Card, Holey, Ring, TaskRow, clock } from "../ui";
import { palette } from "../theme";
import { sans } from "./fonts";
import { NOTCH_H, NOTCH_W, SW } from "./Mac";

export const PANEL_W = 1064;
export const PANEL_H = 320;
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/**
 * The workspace, drawn in screen coordinates hanging from the notch. `open` grows the black shape
 * out of the notch and the shape clips the cards as it grows — the same reveal the app uses.
 */
export const Panel: React.FC<{
  open: number;
  done?: number;
  added?: string[];
  addedIn?: number;
  running?: boolean;
  tab?: "workspace" | "insights";
  /** 0..1 pulse that makes Holey jump, as the app does when a task is finished. */
  cheer?: number;
}> = ({ open, done = 0, added = [], addedIn = 1, running = false, tab = "workspace", cheer = 0 }) => {
  const w = interpolate(open, [0, 1], [NOTCH_W, PANEL_W]);
  const h = interpolate(open, [0, 1], [NOTCH_H, PANEL_H]);
  const r = interpolate(open, [0, 1], [12, 28]);
  const content = interpolate(open, [0.35, 1], [0, 1], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: SW / 2 - w / 2,
        top: 0,
        width: w,
        height: h,
        background: "#000",
        borderRadius: `0 0 ${r}px ${r}px`,
        overflow: "hidden",
        boxShadow: open > 0.05 ? `0 ${24 * open}px ${60 * open}px rgba(0,0,0,${0.28 * open})` : "none"
      }}
    >
      <div
        style={{
          position: "absolute",
          left: w / 2 - PANEL_W / 2,
          top: 0,
          width: PANEL_W,
          padding: "0 24px",
          boxSizing: "border-box",
          opacity: content,
          transform: `scale(${interpolate(content, [0, 1], [0.95, 1])})`,
          transformOrigin: "top center",
          fontFamily: sans
        }}
      >
        <div style={{ height: 44, display: "flex", alignItems: "center", gap: 10, color: "#fff" }}>
          <Holey size={24} bounce={cheer} />
          <span style={{ fontSize: 15, fontWeight: 600 }}>Black Hole</span>
          <span style={{ flex: 1 }} />
          {["Workspace", "Insights", "Settings"].map((t) => (
            <span
              key={t}
              style={{
                fontSize: 12.5,
                padding: "5px 11px",
                borderRadius: 8,
                background: t.toLowerCase() === tab ? palette.chrome : "transparent",
                color: "rgba(255,255,255,0.88)"
              }}
            >
              {t}
            </span>
          ))}
        </div>
        {tab === "insights" ? <Insights /> : (
          <div style={{ display: "flex", gap: 8 }}>
            <Card tint={palette.tasks} width={316} title="Today's tasks" icon="☰">
              <div style={{ background: palette.well, borderRadius: 12, padding: "9px 12px", fontSize: 13, color: palette.inkSecondary }}>
                ＋ What needs doing?
              </div>
              {added.length > 0 ? null : (
                <>
                  <TaskRow title="Ship the launch video" done={done} meta="45m" />
                  <TaskRow title="Reply to Show HN" meta="Today 3:00 PM" />
                </>
              )}
              {added.map((title, i) => {
                const t = interpolate(addedIn, [i / added.length, (i + 0.6) / added.length], [0, 1], clamp);
                return (
                  <div key={title} style={{ opacity: t, transform: `translateY(${(1 - t) * -10}px)` }}>
                    <TaskRow title={title} />
                  </div>
                );
              })}
            </Card>
            <Card tint={palette.timer} width={172} title="" icon="">
              <div style={{ textAlign: "center", marginTop: 18 }}>
                <div style={{ fontSize: 42, fontWeight: 700, letterSpacing: "0.03em" }}>{running ? "24:59" : "25:00"}</div>
                <div style={{ fontSize: 12, color: palette.inkSecondary }}>{running ? "Remaining" : "Ready"}</div>
                <div style={{ margin: "34px auto 0", width: 96, padding: "8px 0", borderRadius: 10, background: palette.ink, color: "#fff", fontSize: 13, fontWeight: 600 }}>
                  {running ? "❚❚ Pause" : "▶ Start"}
                </div>
              </div>
            </Card>
            <Card tint={palette.notepad} width={182} title="Notepad" icon="✎">
              <div style={{ fontSize: 13, lineHeight: 1.55 }}>
                Launch day
                <br />— record the film
                <br />— post it
                <br />— thank everyone
              </div>
            </Card>
            <Card tint={palette.events} width={152} title="Events" icon="▦">
              <div style={{ background: palette.wellStrong, borderRadius: 11, padding: 9, fontSize: 12.5 }}>
                <b>Design review</b>
                <div style={{ fontSize: 11, color: palette.inkSecondary }}>11:00 – 11:30</div>
              </div>
            </Card>
            <Card tint={palette.music} width={168} title="Playing" icon="♪">
              <div style={{ display: "flex", gap: 9 }}>
                <div style={{ width: 42, height: 42, borderRadius: 7, background: "linear-gradient(135deg,#d9a38f,#8c6f9e)" }} />
                <div style={{ fontSize: 12.5, fontWeight: 600 }}>
                  Slow mornings
                  <div style={{ fontSize: 11, fontWeight: 400, color: palette.inkSecondary }}>Focus mix</div>
                </div>
              </div>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
};

const Insights: React.FC = () => (
  <div style={{ display: "flex", gap: 8 }}>
    <Card tint={palette.tasks} width={300} title="Last 7 days" icon="◔">
      <div style={{ fontSize: 40, fontWeight: 700, letterSpacing: "-0.02em" }}>6h 50m</div>
      <div style={{ fontSize: 12, color: palette.inkSecondary }}>Time focused</div>
      <div style={{ marginTop: "auto", fontSize: 12.5, display: "grid", gap: 6 }}>
        <span>Active days <b style={{ float: "right" }}>6 of 7</b></span>
        <span>Current streak <b style={{ float: "right" }}>4d</b></span>
      </div>
    </Card>
    <Card tint={palette.timer} width={708} title="Focus minutes" icon="▥">
      <div style={{ display: "flex", alignItems: "flex-end", gap: 18, height: 170, padding: "0 12px" }}>
        {[22, 48, 8, 18, 72, 92, 34].map((v, i) => (
          <div key={i} style={{ flex: 1, height: `${v}%`, background: palette.ink, borderRadius: "5px 5px 2px 2px" }} />
        ))}
      </div>
    </Card>
  </div>
);

/** The notch as a live timer: ring on one side, time on the other, the camera between. */
export const Island: React.FC<{ seconds: number; total?: number; show?: number }> = ({ seconds, total = 1500, show = 1 }) => {
  const wing = 78;
  return (
    <div
      style={{
        position: "absolute",
        left: SW / 2 - NOTCH_W / 2 - wing * show,
        top: 0,
        width: NOTCH_W + wing * 2 * show,
        height: NOTCH_H,
        background: "#000",
        borderRadius: "0 0 13px 13px",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 14px",
        boxSizing: "border-box",
        fontFamily: sans
      }}
    >
      <div style={{ opacity: show }}>
        <Ring progress={1 - seconds / total} size={18} />
      </div>
      <span style={{ opacity: show, color: palette.islandAccent, fontWeight: 650, fontSize: 14.5, fontVariantNumeric: "tabular-nums" }}>
        {clock(seconds)}
      </span>
    </div>
  );
};

/** The next meeting in the notch: what it is, and how long you have. */
export const MeetingIsland: React.FC<{ seconds: number }> = ({ seconds }) => {
  const wing = 122;
  return (
    <div
      style={{
        position: "absolute",
        left: SW / 2 - NOTCH_W / 2 - wing,
        top: 0,
        width: NOTCH_W + wing * 2,
        height: NOTCH_H,
        background: "#000",
        borderRadius: "0 0 13px 13px",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 14px",
        boxSizing: "border-box",
        fontFamily: sans,
        color: "#fff",
        fontSize: 13
      }}
    >
      <span><span style={{ color: "#62B6FF" }}>■ </span>Design review</span>
      <span style={{ color: palette.soon, fontWeight: 650, fontVariantNumeric: "tabular-nums" }}>{clock(seconds)}</span>
    </div>
  );
};

/** The ⌥Space bar, just under the menu bar. */
export const CommandBar: React.FC<{ text: string; caret: boolean; pill?: string; pillIn?: number; show: number }> = ({
  text,
  caret,
  pill,
  pillIn = 0,
  show
}) => (
  <div
    style={{
      position: "absolute",
      left: SW / 2 - 300,
      top: NOTCH_H + 14 + (1 - show) * -16,
      width: 600,
      height: 60,
      borderRadius: 17,
      background: "#000",
      border: "1px solid rgba(255,255,255,0.08)",
      boxShadow: "0 24px 60px rgba(0,0,0,0.3)",
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "0 18px",
      boxSizing: "border-box",
      opacity: show,
      fontFamily: sans
    }}
  >
    <Holey size={24} />
    <span style={{ color: text ? "#fff" : "rgba(255,255,255,0.4)", fontSize: 17, fontWeight: 500, flex: 1, whiteSpace: "nowrap" }}>
      {text || "Add to your day, or type a command…"}
      {caret ? <span style={{ color: "#7AA7FF", marginLeft: 1 }}>|</span> : null}
    </span>
    {pill ? (
      <span style={{ fontSize: 12.5, color: "rgba(255,255,255,0.78)", padding: "5px 10px", borderRadius: 999, background: "rgba(255,255,255,0.12)", opacity: pillIn, whiteSpace: "nowrap" }}>
        {pill}
      </span>
    ) : null}
  </div>
);
