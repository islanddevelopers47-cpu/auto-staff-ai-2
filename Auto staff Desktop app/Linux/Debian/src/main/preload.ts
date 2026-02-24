// Minimal preload script for Claw Staffer Desktop
// The app runs entirely via the embedded Express server,
// so no special Node.js APIs are exposed to the renderer.
import { contextBridge } from "electron";

contextBridge.exposeInMainWorld("desktop", {
  isDesktop: true,
  platform: process.platform,
  version: process.env.npm_package_version || "1.0.0",
});
