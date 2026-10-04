import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setJpegQuality(95);
// x264 at a quality that survives X and LinkedIn re-encoding without banding on the dark gradients.
Config.setCodec("h264");
Config.setCrf(16);
