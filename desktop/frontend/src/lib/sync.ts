import { PERSISTED_KEYS, useLibrary, type LibraryState } from "@/store/library";
import { useSession } from "@/store/session";
import type { Session } from "@/platform";
import { api, ApiError } from "./api";
import type { Collection, SyncRecord } from "./types";

type Op =
  | { kind: "put"; collection: Collection; record: SyncRecord }
  | { kind: "deleteFolder"; id: string };

type Broadcast = { collection: Collection; records: SyncRecord[] };

const RETRY_MS = 5_000;
const POLL_MS = 60_000;

/**
 * Keeps the local library in sync with the server:
 * writes are applied locally first and queued in a persistent outbox, other windows
 * hear about them instantly over a BroadcastChannel, and other devices through the
 * server's event stream which triggers an incremental pull.
 */
class SyncEngine {
  private session: Session | null = null;
  private events: EventSource | null = null;
  private channel: BroadcastChannel | null = null;
  private outbox: Op[] = [];
  private flushing = false;
  private pulling = false;
  private pullAgain = false;
  private retryTimer = 0;
  private pollTimer = 0;
  private unsubscribeStore: (() => void) | null = null;

  start(session: Session) {
    this.stop();
    this.session = session;

    const snapshot = this.readSnapshot();
    useLibrary.getState().reset(snapshot ? { ...snapshot, ready: true } : undefined);
    this.outbox = this.read<Op[]>(this.key("outbox")) ?? [];

    this.channel = new BroadcastChannel(`reader:${session.email}`);
    this.channel.onmessage = ({ data }: MessageEvent<Broadcast>) => useLibrary.getState().merge(data.collection, data.records);

    this.events = new EventSource(api.eventsUrl(session));
    this.events.addEventListener("version", (e) => {
      if (Number((e as MessageEvent).data) > useLibrary.getState().version) void this.pull();
    });
    this.events.onopen = () => void this.flush();

    let saveTimer = 0;
    this.unsubscribeStore = useLibrary.subscribe(() => {
      clearTimeout(saveTimer);
      saveTimer = window.setTimeout(() => this.writeSnapshot(), 800);
    });

    window.addEventListener("online", this.onOnline);
    this.pollTimer = window.setInterval(() => void this.pull(), POLL_MS);

    void this.pull();
    void this.flush();
  }

  stop() {
    this.events?.close();
    this.channel?.close();
    this.unsubscribeStore?.();
    clearTimeout(this.retryTimer);
    clearInterval(this.pollTimer);
    window.removeEventListener("online", this.onOnline);
    this.events = this.channel = this.unsubscribeStore = this.session = null;
  }

  /** Saves a record locally and queues it for the server. */
  put<T extends SyncRecord>(collection: Collection, record: T) {
    const stamped = { ...record, modifiedAt: Math.max(Date.now(), record.modifiedAt + 1) };
    this.applyLocal(collection, [stamped]);
    this.enqueue({ kind: "put", collection, record: stamped });
    return stamped;
  }

  /** Deletes a folder; its books and subfolders move up one level. */
  deleteFolder(id: string) {
    const { folders, books } = useLibrary.getState();
    const parentId = folders[id]?.parentId ?? null;
    const now = Date.now();
    this.applyLocal("books", Object.values(books).filter((b) => b.folderId === id).map((b) => ({ ...b, folderId: parentId, modifiedAt: now })));
    this.applyLocal("folders", [
      ...Object.values(folders).filter((f) => f.parentId === id).map((f) => ({ ...f, parentId, modifiedAt: now })),
      { ...folders[id], deleted: true, modifiedAt: now },
    ]);
    this.enqueue({ kind: "deleteFolder", id });
  }

  /** Records that were created on the server directly (uploads). */
  received(collection: Collection, record: SyncRecord) {
    this.applyLocal(collection, [record]);
  }

  async pull() {
    if (!this.session) return;
    if (this.pulling) {
      this.pullAgain = true;
      return;
    }
    this.pulling = true;
    try {
      do {
        this.pullAgain = false;
        const changes = await api.sync(this.session, useLibrary.getState().version);
        useLibrary.getState().applyChanges(changes);
      } while (this.pullAgain);
    } catch (err) {
      this.handleError(err);
      useLibrary.setState({ ready: true });
    } finally {
      this.pulling = false;
    }
  }

  private applyLocal(collection: Collection, records: SyncRecord[]) {
    if (!records.length) return;
    useLibrary.getState().merge(collection, records);
    this.channel?.postMessage({ collection, records } satisfies Broadcast);
  }

  private enqueue(op: Op) {
    const same = (o: Op) =>
      o.kind === "put" && op.kind === "put" && o.collection === op.collection && o.record.id === op.record.id;
    this.outbox = [...this.outbox.filter((o) => !same(o)), op];
    this.write(this.key("outbox"), this.outbox);
    void this.flush();
  }

  private async flush() {
    if (this.flushing || !this.session) return;
    this.flushing = true;
    try {
      while (this.outbox.length && this.session) {
        const op = this.outbox[0];
        try {
          if (op.kind === "put") {
            const saved = await api.put(this.session, op.collection, op.record);
            useLibrary.getState().merge(op.collection, [saved]);
          } else {
            await api.deleteFolder(this.session, op.id);
          }
        } catch (err) {
          if (!(err instanceof ApiError) || err.status === 0 || err.status >= 500) {
            this.retryTimer = window.setTimeout(() => void this.flush(), RETRY_MS);
            return;
          }
          this.handleError(err);
        }
        this.outbox = this.outbox.filter((o) => o !== op);
        this.write(this.key("outbox"), this.outbox);
      }
    } finally {
      this.flushing = false;
    }
  }

  private handleError(err: unknown) {
    if (err instanceof ApiError && err.status === 401) void useSession.getState().signOut();
    else console.warn("sync:", err);
  }

  private onOnline = () => {
    void this.flush();
    void this.pull();
  };

  private key(name: string) {
    return `reader:${name}:${this.session?.email}`;
  }

  private readSnapshot() {
    return this.read<Partial<LibraryState>>(this.key("snapshot"));
  }

  private writeSnapshot() {
    if (!this.session) return;
    const state = useLibrary.getState();
    this.write(this.key("snapshot"), Object.fromEntries(PERSISTED_KEYS.map((k) => [k, state[k]])));
  }

  private read<T>(key: string): T | null {
    try {
      const raw = localStorage.getItem(key);
      return raw ? (JSON.parse(raw) as T) : null;
    } catch {
      return null;
    }
  }

  private write(key: string, value: unknown) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (err) {
      console.warn("storage:", err);
    }
  }
}

export const sync = new SyncEngine();
