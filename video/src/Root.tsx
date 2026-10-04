import React from "react";
import { Composition } from "remotion";
import { Launch, totalFrames } from "./Launch";
import { FPS } from "./theme";

export const Root: React.FC = () => (
  <>
    {/* 16:9 for X, YouTube and the website. */}
    <Composition id="Launch" component={Launch} durationInFrames={totalFrames(FPS)} fps={FPS} width={1920} height={1080} />
    {/* 1:1 and 4:5 take more of the feed on LinkedIn and on phones. */}
    <Composition id="LaunchSquare" component={Launch} durationInFrames={totalFrames(FPS)} fps={FPS} width={1080} height={1080} />
    <Composition id="LaunchVertical" component={Launch} durationInFrames={totalFrames(FPS)} fps={FPS} width={1080} height={1350} />
  </>
);
