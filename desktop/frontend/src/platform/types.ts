import type { Book } from "@/lib/types";

export interface Session {
  serverUrl: string;
  token: string;
  email: string;
}

/** Everything that differs between the desktop shell and a plain browser. */
export interface Platform {
  readonly os: string;
  /** True when this window only shows a single book. */
  readonly standalone: boolean;

  loadSession(): Promise<Session | null>;
  saveSession(session: Session): Promise<void>;
  clearSession(): Promise<void>;

  bookFile(book: Book, session: Session): Promise<Blob>;
  coverUrl(book: Book, session: Session): string;

  openReaderWindow(book: Book): Promise<void>;
  setPinned(pinned: boolean): Promise<boolean>;
  setTitle(title: string): void;
  openUrl(url: string): void;
  closeWindow(): void;

  /** Subscribes to files dropped onto the window from the OS. */
  onFilesDropped(callback: (files: File[]) => void): () => void;
}

export function remoteUrl(session: Session, path: string) {
  return `${session.serverUrl.replace(/\/+$/, "")}/api${path}`;
}
