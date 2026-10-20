import { Browser, Events } from "@wailsio/runtime";
import * as SessionService from "../../bindings/github.com/mebn/reader/desktop/internal/session/service";
import * as WindowService from "../../bindings/github.com/mebn/reader/desktop/internal/windows/service";
import type { Platform, Session } from "./types";

export async function createWailsPlatform(): Promise<Platform> {
  const os = await WindowService.Platform();

  return {
    os,
    standalone: location.hash.startsWith("#/window/"),

    async loadSession() {
      const s = await SessionService.Get();
      return s.serverUrl ? s : null;
    },
    async saveSession(session: Session) {
      await SessionService.Set(session);
    },
    async clearSession() {
      await SessionService.Clear();
    },

    async bookFile(book) {
      const res = await fetch(`/cache/books/${book.id}`);
      if (!res.ok) throw new Error(await res.text());
      return res.blob();
    },
    coverUrl(book) {
      return `/cache/covers/${book.id}?v=${book.modifiedAt}`;
    },

    async openReaderWindow(book) {
      await WindowService.OpenReader(book.id, book.title);
    },
    setPinned: (pinned) => WindowService.SetPinned(pinned),
    setTitle: (title) => void WindowService.SetTitle(title),
    openUrl: (url) => void Browser.OpenURL(url),
    closeWindow: () => void WindowService.Close(),

    onFilesDropped(callback) {
      return Events.On("files:dropped", async (event) => {
        const files = await Promise.all(
          event.data.map(async ({ name, url }) => new File([await (await fetch(url)).blob()], name)),
        );
        callback(files);
      });
    },
  };
}
