import type { Platform } from "./types";

export type { Platform, Session } from "./types";

let current: Platform | null = null;

/** WebView2 and WKWebView expose their native message bridges here. */
function inDesktopShell() {
  const w = window as any;
  return Boolean(w.chrome?.webview || w.webkit?.messageHandlers);
}

export async function initPlatform(): Promise<Platform> {
  current = inDesktopShell()
    ? await (await import("./wails")).createWailsPlatform()
    : (await import("./web")).createWebPlatform();
  document.documentElement.dataset.platform = current.os;
  return current;
}

export function platform(): Platform {
  if (!current) throw new Error("platform not initialised");
  return current;
}
