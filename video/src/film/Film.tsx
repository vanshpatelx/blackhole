import React from "react";
import { useFilmFrame } from "./tempo";
import {AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useVideoConfig} from "remotion";
import { Card, Holey, TaskRow } from "../ui";
import { palette } from "../theme";
import { Cursor } from "./Cursor";
import { inkColor, paper, sans, serif } from "./fonts";
import { Grain } from "./Grain";
import { BEAT, cue, factorOf, lengthOf, startOf, type Section } from "./grid";
import { Tempo } from "./tempo";
import { Camera, MacScreen, SW } from "./Mac";
import { CommandBar, Island, MeetingIsland, Panel } from "./Panel";
import { Words } from "./Type";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);
/** Pick a zoom for 16:9 or for the narrow cuts, where the base scale already fills the width. */
const useZoom = () => {
  const { width, height } = useVideoConfig();
  const wide = width / height >= 1.5;
  return (forWide: number, forNarrow: number) => (wide ? forWide : forNarrow);
};
const Paper: React.FC<{ children?: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: paper, fontFamily: sans }}>{children}</AbsoluteFill>
);

/** A line set inside the screen, so it scales and crops with the camera like everything else on it. */
const ScreenLine: React.FC<{ words: { text: string; at: number; serif?: boolean }[]; top: number; px: number }> = ({ words, top, px }) => {
  const frame = useFilmFrame();
  return (
    <div style={{ position: "absolute", left: SW / 2 - 560, width: 1120, top, textAlign: "center", fontFamily: sans, fontSize: px, fontWeight: 600, letterSpacing: "-0.035em", color: inkColor, lineHeight: 1.08 }}>
      {words.map((w, i) => {
        const t = 1 - Math.pow(1 - interpolate(frame, [w.at, w.at + 7], [0, 1], clamp), 3);
        return (
          <span key={i} style={{ display: "inline-block", marginRight: "0.24em", opacity: t, filter: `blur(${(1 - t) * 10}px)`, transform: `translateY(${(1 - t) * 0.28}em)`, ...(w.serif ? { fontFamily: serif, fontStyle: "italic", fontWeight: 400, fontSize: "1.12em", letterSpacing: "-0.01em" } : {}) }}>
            {w.text}
          </span>
        );
      })}
    </div>
  );
};

// ── 1 · Hook (bars 1–2) — the problem, word by word on the beat ──────────────────────────────
const Hook: React.FC = () => {
  const frame = useFilmFrame();
  return (
    <Paper>
      {frame < 60 ? (
        <Words words={[{ text: "You", at: 0 }, { text: "have", at: 8 }, { text: "a", at: 15 }, { text: "to-do list.", at: 22 }]} size={1.15} />
      ) : (
        <Words words={[{ text: "You", at: 60 }, { text: "never", at: 68 }, { text: "look", at: 75, serif: true }, { text: "at it.", at: 83 }]} size={1.15} />
      )}
    </Paper>
  );
};

// ── 2 · Build (bars 3–4) — the screen, and a hand heading for the notch ──────────────────────
const Build: React.FC = () => {
  const frame = useFilmFrame();
  const zoom = interpolate(frame, [0, 120], [1, 1.1], clamp);
  return (
    <Paper>
      <Camera zoom={zoom}>
        <MacScreen>
          <ScreenLine
            top={470}
            px={74}
            words={[{ text: "So", at: 18 }, { text: "we", at: 30 }, { text: "put", at: 42 }, { text: "it", at: 54 }, { text: "here.", at: 96, serif: true }]}
          />
          <Cursor path={[{ frame: 22, x: 1370, y: 900 }, { frame: 70, x: 1010, y: 520 }, { frame: 114, x: SW / 2 + 6, y: 16 }]} scale={1.15} />
        </MacScreen>
      </Camera>
    </Paper>
  );
};

// ── 3–5 · Drop, tick, start (bars 5–7) — one continuous take on the screen ───────────────────
const Workday: React.FC = () => {
  const frame = useFilmFrame();
  const { fps } = useVideoConfig();
  const open = spring({ frame, fps, config: { damping: 15, stiffness: 120, mass: 0.9 } });
  const collapse = spring({ frame: frame - 165, fps, config: { damping: 200, stiffness: 180 } });
  const panelOpen = frame < 165 ? open : 1 - collapse;
  const done = interpolate(frame, [90, 102], [0, 1], clamp);
  const cheer = interpolate(frame, [90, 97, 106], [0, 1, 0], clamp);
  const z = useZoom();
  // Open wide for context, then push in so the cards are readable — on a phone especially.
  const push = interpolate(frame, [22, 52], [0, 1], { ...clamp, easing: easeOut });
  const zoom = interpolate(push, [0, 1], [1.08, z(1.62, 1)]);
  const target = interpolate(push, [0, 1], [0, 165]);
  const place = interpolate(push, [0, 1], [z(0.06, 0.06), z(0.45, 0.42)]);
  return (
    <Paper>
      <Camera zoom={zoom} y={target} placeY={push === 0 ? undefined : place}>
        <MacScreen>
          <ScreenLine top={470} px={66} words={[]} />
          <Panel open={Math.max(0, panelOpen)} done={done} cheer={cheer} running={frame >= 150} />
          {frame >= 165 ? <Island seconds={1499} show={collapse} /> : null}
          <Cursor
            path={[
              { frame: 0, x: SW / 2 + 6, y: 16 },
              { frame: 40, x: SW / 2 + 60, y: 120 },
              { frame: 74, x: 266, y: 146 },
              { frame: 90, x: 266, y: 146, click: true },
              { frame: 132, x: 648, y: 184 },
              { frame: 150, x: 648, y: 184, click: true },
              { frame: 178, x: 960, y: 420 }
            ]}
            scale={1.15}
          />
        </MacScreen>
      </Camera>
    </Paper>
  );
};

// ── 6 · The notch keeps time (bar 8) ─────────────────────────────────────────────────────────
const Keeps: React.FC = () => {
  const frame = useFilmFrame();
  const { fps } = useVideoConfig();
  const push = spring({ frame, fps, config: { damping: 26, mass: 1 } });
  const seconds = 1499 - frame * 1.9;
  const z = useZoom();
  return (
    <Paper>
      <Camera zoom={interpolate(push, [0, 1], [z(1.62, 1), z(3.3, 2.75)])} placeY={interpolate(push, [0, 1], [z(0.12, 0.1), 0.36])}>
        <MacScreen>
          <Island seconds={seconds} />
        </MacScreen>
      </Camera>
      <Words words={[{ text: "The", at: 14 }, { text: "notch", at: 20 }, { text: "keeps", at: 27 }, { text: "time.", at: 34, serif: true }]} y={0.74} size={0.9} />
    </Paper>
  );
};

// ── 7 · Or skip the mouse (bars 9–10) ────────────────────────────────────────────────────────
const Key: React.FC<{ label: string; pressAt: number; wide?: boolean; showAt: number }> = ({ label, pressAt, wide, showAt }) => {
  const frame = useFilmFrame();
  const { width, height } = useVideoConfig();
  const k = Math.min(width, height * 1.6) / 1100;
  const pressed = frame >= pressAt && frame < pressAt + 9;
  const show = interpolate(frame, [showAt, showAt + 6], [0, 1], clamp);
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: (wide ? 230 : 84) * k,
        height: 84 * k,
        margin: `0 ${10 * k}px`,
        borderRadius: 18 * k,
        background: pressed ? "#E4DFD6" : "#FBF9F5",
        color: inkColor,
        fontFamily: sans,
        fontSize: 30 * k,
        fontWeight: 500,
        boxShadow: pressed ? `0 ${2 * k}px 0 #CFC8BC` : `0 ${7 * k}px 0 #CFC8BC, 0 ${12 * k}px ${26 * k}px rgba(60,40,20,0.14)`,
        transform: `translateY(${pressed ? 5 * k : 0}px)`,
        opacity: show
      }}
    >
      {label}
    </span>
  );
};

const Command: React.FC = () => {
  const frame = useFilmFrame();
  const { fps, height } = useVideoConfig();
  // Hooks before any early return: React needs the same ones every frame.
  const z = useZoom();
  if (frame < 60) {
    return (
      <Paper>
        <Words words={[{ text: "Or", at: 0 }, { text: "skip", at: 8 }, { text: "the", at: 15 }, { text: "mouse.", at: 22, serif: true }]} y={0.36} size={1.05} />
        <div style={{ position: "absolute", left: 0, right: 0, top: height * 0.62, textAlign: "center" }}>
          <Key label="⌥" showAt={24} pressAt={30} />
          <Key label="space" wide showAt={26} pressAt={45} />
        </div>
      </Paper>
    );
  }
  const typed = "call mika tomorrow at 3pm";
  const chars = Math.floor(interpolate(frame, [64, 100], [0, typed.length], clamp));
  const show = spring({ frame: frame - 60, fps, config: { damping: 200 } });
  return (
    <Paper>
      <Camera zoom={z(2.45, 1.62)} y={81} placeY={0.46}>
        <MacScreen>
          <CommandBar text={typed.slice(0, chars)} caret={frame % 24 < 14} pill="Tomorrow · 3:00 PM" pillIn={interpolate(frame, [104, 110], [0, 1], clamp)} show={show} />
        </MacScreen>
      </Camera>
    </Paper>
  );
};

// ── 8 · Or ask your assistant (bars 11–12) ───────────────────────────────────────────────────
const Ask: React.FC = () => {
  const frame = useFilmFrame();
  const { width, height } = useVideoConfig();
  const z = useZoom();
  if (frame < 60) {
    const msg = "Add my three most urgent issues to today.";
    const n = Math.floor(interpolate(frame, [4, 44], [0, msg.length], clamp));
    const cardW = Math.min(width * 0.7, height * 1.2);
    const k = cardW / 700;
    const sent = frame >= 50;
    return (
      <Paper>
        <div style={{ position: "absolute", left: width / 2 - cardW / 2, top: height * 0.5 - 90 * k, width: cardW }}>
          <div style={{ fontFamily: sans, fontSize: 15 * k, color: "rgba(22,22,26,0.5)", marginBottom: 12 * k, fontWeight: 500 }}>Your AI assistant</div>
          <div style={{ background: "#fff", borderRadius: 26 * k, padding: `${26 * k}px ${28 * k}px`, boxShadow: "0 30px 70px rgba(60,40,20,0.12), 0 0 0 1px rgba(0,0,0,0.05)", display: "flex", alignItems: "flex-end", gap: 16 * k }}>
            <div style={{ flex: 1, fontFamily: sans, fontSize: 26 * k, color: inkColor, minHeight: 64 * k, lineHeight: 1.3 }}>
              {msg.slice(0, n)}
              {frame % 24 < 14 && !sent ? <span style={{ color: "#7AA7FF" }}>|</span> : null}
            </div>
            <div style={{ width: 46 * k, height: 46 * k, borderRadius: 999, background: inkColor, color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22 * k, transform: `scale(${sent && frame < 56 ? 0.88 : 1})` }}>↑</div>
          </div>
        </div>
      </Paper>
    );
  }
  return (
    <Paper>
      <Camera zoom={z(1.5, 1)} y={190} placeY={z(0.43, 0.4)}>
        <MacScreen>
          <Panel open={1} added={["Fix login redirect", "Bump the DMG version", "Answer the security report"]} addedIn={interpolate(frame, [62, 100], [0, 1], clamp)} />
          <ScreenLine top={350} px={46} words={[{ text: "Works", at: 70 }, { text: "with", at: 76 }, { text: "Claude", at: 82 }, { text: "and", at: 88 }, { text: "ChatGPT.", at: 94, serif: true }]} />
        </MacScreen>
      </Camera>
    </Paper>
  );
};

// ── 9 · Montage (bars 13–14): a cut on every beat ────────────────────────────────────────────
const Label: React.FC<{ text: string }> = ({ text }) => {
  const { height, width } = useVideoConfig();
  const frame = useFilmFrame();
  const t = interpolate(frame, [1, 6], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: height * 0.85, transform: "translateY(-50%)", textAlign: "center", fontFamily: serif, fontStyle: "italic", fontSize: Math.min(width * 0.06, height * 0.1), color: inkColor, opacity: t, letterSpacing: "-0.01em" }}>
      {text}
    </div>
  );
};

/** Pops a UI element in, scaled so its height is `fill` of the frame — clear of the label below it. */
const Pop: React.FC<{ children: React.ReactNode; h: number; fill?: number; y?: number }> = ({ children, h, fill = 0.56, y = 0.41 }) => {
  const { width, height } = useVideoConfig();
  const frame = useFilmFrame();
  const p = interpolate(frame, [0, 5], [0.93, 1], { ...clamp, easing: (t) => 1 - Math.pow(1 - t, 3) });
  return (
    <div style={{ position: "absolute", left: width / 2, top: height * y, transform: `translate(-50%, -50%) scale(${Math.min((height * fill) / h, (width * 0.84) / (h * 1.8)) * p})` }}>{children}</div>
  );
};

const Montage: React.FC = () => {
  const z = useZoom();
  const shots: React.ReactNode[] = [
    <Paper key="m"><Camera zoom={z(3.1, 2.0)} placeY={0.32}><MacScreen><MeetingIsland seconds={299} /></MacScreen></Camera><Label text="Your next meeting." /></Paper>,
    <Paper key="s"><Pop h={266}><Card tint={palette.music} width={260} title="Playing" icon="♪"><div style={{ display: "flex", gap: 12 }}><div style={{ width: 64, height: 64, borderRadius: 10, background: "linear-gradient(135deg,#d9a38f,#8c6f9e)" }} /><div style={{ fontSize: 15, fontWeight: 600 }}>Slow mornings<div style={{ fontSize: 12.5, fontWeight: 400, color: palette.inkSecondary }}>Focus mix</div></div></div><div style={{ marginTop: "auto", display: "flex", gap: 22, justifyContent: "center", fontSize: 18 }}><span>⏮</span><span>❚❚</span><span>⏭</span></div></Card></Pop><Label text="Your music." /></Paper>,
    <Paper key="i"><Camera zoom={z(1.75, 1)} x={SW / 2} y={175} placeY={0.4}><MacScreen><Panel open={1} tab="insights" /></MacScreen></Camera><Label text="Your week." /></Paper>,
    <Paper key="r"><Pop h={266}><Card tint={palette.tasks} width={300} title="Today's tasks" icon="☰"><TaskRow title="Standup" meta="↻ Weekdays · 9:00 AM" /><TaskRow title="Water the plants" meta="↻ Daily" /></Card></Pop><Label text="Things that repeat." /></Paper>,
    <Paper key="n"><Pop h={266}><Card tint={palette.notepad} width={300} title="Notepad" icon="✎"><div style={{ fontSize: 13, lineHeight: 1.6 }}>Launch day<br /><span style={{ background: "rgba(0,0,0,0.12)", borderRadius: 4, padding: "1px 4px" }}>— email the press list</span><br />— thank everyone</div><div style={{ marginTop: "auto", fontSize: 12, color: palette.inkSecondary }}>⌘↩ turns a line into a task</div></Card></Pop><Label text="Notes become tasks." /></Paper>,
    <Paper key="o"><Pop h={430} fill={0.6}><Orb /></Pop><Label text="On any screen." /></Paper>,
    <Paper key="h"><Pop h={300} fill={0.42}><Img src={staticFile("moods.png")} style={{ width: 790 }} /></Pop><Label text="And Holey." /></Paper>,
    <Paper key="f"><Words words={[{ text: "Free.", at: 0 }, { text: "Open", at: 5 }, { text: "source.", at: 9, serif: true }]} size={1.2} /></Paper>
  ];
  return (
    <>
      {shots.map((shot, i) => (
        <Sequence key={i} from={i * BEAT} durationInFrames={BEAT}>
          {shot}
        </Sequence>
      ))}
    </>
  );
};

/** A second display with the floating button parked on its edge and the workspace open beside it. */
const Orb: React.FC = () => (
  <div style={{ width: 760, height: 430, borderRadius: 22, background: "#0B0B0D", padding: 12, boxSizing: "border-box", boxShadow: "0 30px 80px rgba(60,40,20,0.2)" }}>
    <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: 12, overflow: "hidden", background: "radial-gradient(60% 70% at 30% 30%, #CEC5F3, rgba(0,0,0,0) 70%), radial-gradient(60% 60% at 80% 80%, #F6C7A6, rgba(0,0,0,0) 70%), #EDE3DA" }}>
      <div style={{ position: "absolute", right: 14, top: 190, width: 58, height: 58, borderRadius: 999, background: "rgba(20,20,24,0.88)", boxShadow: "0 10px 30px rgba(0,0,0,0.35)", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Holey size={34} />
      </div>
      <div style={{ position: "absolute", right: 86, top: 120, width: 420, height: 200, borderRadius: 20, background: "#000", padding: 10, boxSizing: "border-box", display: "flex", gap: 6 }}>
        {[palette.tasks, palette.timer, palette.notepad].map((c) => <div key={c} style={{ flex: 1, borderRadius: 12, background: c }} />)}
      </div>
    </div>
  </div>
);

// ── 10 · End card (bars 15–16) ───────────────────────────────────────────────────────────────
const End: React.FC = () => {
  const frame = useFilmFrame();
  const { fps, width, height } = useVideoConfig();
  const u = Math.min(width * 0.05, height * 0.085);
  const logo = spring({ frame, fps, config: { damping: 13, mass: 0.8 } });
  const show = (f: number) => interpolate(frame, [f, f + 8], [0, 1], clamp);
  return (
    <Paper>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: u * 0.3 }}>
        <div style={{ transform: `scale(${logo})` }}><Holey size={u * 2.3} /></div>
        <div style={{ fontFamily: sans, fontWeight: 700, fontSize: u * 1.25, letterSpacing: "-0.045em", color: inkColor, opacity: show(6) }}>Black Hole</div>
        <div style={{ fontFamily: serif, fontStyle: "italic", fontSize: u * 0.72, color: inkColor, opacity: show(18) }}>Your whole day, one hover away.</div>
        <div style={{ marginTop: u * 0.35, fontFamily: sans, fontSize: u * 0.36, fontWeight: 500, color: "rgba(22,22,26,0.62)", opacity: show(32) }}>
          Free and open source for Mac · <span style={{ color: inkColor, fontWeight: 600 }}>getblackhole.app</span>
        </div>
      </div>
    </Paper>
  );
};

// ── Sound ────────────────────────────────────────────────────────────────────────────────────
// Each cue is written against its section's original timing and placed by the same grid as the
// pictures, so retiming a section moves its sounds with it.
const cues: Array<[Section, number, string, number]> = [
  ["hook", 0, "tick", 0.5], ["hook", 8, "tick", 0.45], ["hook", 15, "tick", 0.45], ["hook", 22, "tick", 0.55],
  ["hook", 60, "tick", 0.5], ["hook", 68, "tick", 0.45], ["hook", 75, "tick", 0.55], ["hook", 83, "tick", 0.5],
  // "here." and the notch opening, leading into the drop.
  ["build", 96, "tick", 0.5], ["build", 104, "whoosh", 0.55],
  // Ticking the task, starting the timer, collapsing into the island.
  ["workday", 90, "click", 0.7], ["workday", 150, "click", 0.7], ["workday", 165, "pop", 0.6],
  ["command", 30, "key", 0.8], ["command", 45, "key", 0.8], ["command", 104, "tick", 0.45],
  ["ask", 50, "click", 0.6], ["ask", 62, "tick", 0.5], ["ask", 75, "tick", 0.5], ["ask", 88, "tick", 0.5],
  ["end", 0, "chime", 0.5]
];
for (let f = 64; f < 100; f += 3) cues.push(["command", f, "type", 0.32]);
for (let f = 4; f < 44; f += 3) cues.push(["ask", f, "type", 0.3]);

const scenes: Array<[Section, React.FC]> = [
  ["hook", Hook], ["build", Build], ["workday", Workday], ["keeps", Keeps],
  ["command", Command], ["ask", Ask], ["montage", Montage], ["end", End]
];

// ── The film ─────────────────────────────────────────────────────────────────────────────────
export const Film: React.FC = () => (
  <AbsoluteFill style={{ background: paper }}>
    {scenes.map(([name, Scene]) => (
      <Sequence key={name} from={startOf(name)} durationInFrames={lengthOf(name)}>
        <Tempo factor={factorOf(name)}>
          <Scene />
        </Tempo>
      </Sequence>
    ))}
    <Grain />
    {/* Headroom: effects land on top of the bed, so the bed sits below full scale. */}
    <Audio src={staticFile("audio/music.wav")} volume={0.74} />
    {cues.map(([section, original, name, vol], i) => (
      <Sequence key={i} from={cue(section, original)}>
        <Audio src={staticFile(`audio/${name}.wav`)} volume={vol} />
      </Sequence>
    ))}
  </AbsoluteFill>
);
