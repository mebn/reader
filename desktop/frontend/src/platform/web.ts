import { remoteUrl, type Platform, type Session } from "./types";

const SESSION_KEY = "reader:session";

/** Browser fallback, used for `npm run dev` outside the desktop shell. */
export function createWebPlatform(): Platform {
  return {
    os: navigator.platform.toLowerCase().includes("mac") ? "darwin" : "web",
    standalone: location.hash.startsWith("#/window/"),

    async loadSession() {
      const raw = localStorage.getItem(SESSION_KEY);
      return raw ? (JSON.parse(raw) as Session) : null;
    },
    async saveSession(session) {
      localStorage.setItem(SESSION_KEY, JSON.stringify(session));
    },
    async clearSession() {
      const current = await this.loadSession();
      localStorage.setItem(SESSION_KEY, JSON.stringify({ serverUrl: current?.serverUrl ?? "", token: "", email: "" }));
    },

    async bookFile(book, session) {
      const res = await fetch(remoteUrl(session, `/books/${book.id}/file`), {
        headers: { Authorization: `Bearer ${session.token}` },
      });
      if (!res.ok) throw new Error(res.statusText);
      return res.blob();
    },
    coverUrl(book, session) {
      return remoteUrl(session, `/books/${book.id}/cover?v=${book.modifiedAt}&token=${session.token}`);
    },

    async openReaderWindow(book) {
      window.open(`${location.pathname}#/window/read/${book.id}`, `reader-${book.id}`, "width=1100,height=800");
    },
    async setPinned() {
      return false;
    },
    setTitle: (title) => void (document.title = title),
    openUrl: (url) => void window.open(url, "_blank", "noopener"),
    closeWindow: () => window.close(),

    onFilesDropped(callback) {
      const prevent = (e: DragEvent) => e.preventDefault();
      const drop = (e: DragEvent) => {
        e.preventDefault();
        const files = Array.from(e.dataTransfer?.files ?? []);
        if (files.length) callback(files);
      };
      window.addEventListener("dragover", prevent);
      window.addEventListener("drop", drop);
      return () => {
        window.removeEventListener("dragover", prevent);
        window.removeEventListener("drop", drop);
      };
    },
  };
}
