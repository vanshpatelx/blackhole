import React from "react";
import { Composition } from "remotion";
import { Film } from "./film/Film";
import { FILM_FRAMES } from "./film/grid";
import { FPS } from "./film/grid";

export const Root: React.FC = () => (
  <>
    {/* 16:9 for X, YouTube and the website. */}
    <Composition id="Launch" component={Film} durationInFrames={FILM_FRAMES} fps={FPS} width={1920} height={1080} />
    {/* 1:1 and 4:5 take more of the feed on LinkedIn and on phones. */}
    <Composition id="LaunchSquare" component={Film} durationInFrames={FILM_FRAMES} fps={FPS} width={1080} height={1080} />
    <Composition id="LaunchVertical" component={Film} durationInFrames={FILM_FRAMES} fps={FPS} width={1080} height={1350} />
  </>
);
