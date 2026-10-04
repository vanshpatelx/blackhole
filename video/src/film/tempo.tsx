import React, { createContext, useContext } from "react";
import { useCurrentFrame } from "remotion";

const Factor = createContext(1);

/** Plays everything inside at `factor` times the speed it was written at. */
export const Tempo: React.FC<{ factor: number; children: React.ReactNode }> = ({ factor, children }) => (
  <Factor.Provider value={factor}>{children}</Factor.Provider>
);

/** The current frame in the section's original timing — use instead of useCurrentFrame in scenes. */
export const useFilmFrame = () => useCurrentFrame() * useContext(Factor);
