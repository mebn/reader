import { create } from "zustand";
import type { Annotation, Book, Changes, Collection, Folder, Progress, Setting, SyncRecord } from "@/lib/types";

type Table<T> = Record<string, T>;

export interface LibraryState {
  folders: Table<Folder>;
  books: Table<Book>;
  progress: Table<Progress>;
  annotations: Table<Annotation>;
  settings: Table<Setting>;
  /** Server version of the last applied pull. */
  version: number;
  ready: boolean;

  /** Merges records by last-write-wins; tombstones remove entries. */
  merge(collection: Collection, records: SyncRecord[]): void;
  applyChanges(changes: Changes): void;
  reset(snapshot?: Partial<LibraryState>): void;
}

const empty = () => ({ folders: {}, books: {}, progress: {}, annotations: {}, settings: {}, version: 0, ready: false });

function mergeTable<T extends SyncRecord>(table: Table<T>, records: T[]): Table<T> {
  if (!records.length) return table;
  const next = { ...table };
  for (const rec of records) {
    const existing = next[rec.id];
    if (existing && existing.modifiedAt > rec.modifiedAt) continue;
    if (rec.deleted) delete next[rec.id];
    else next[rec.id] = rec;
  }
  return next;
}

export const useLibrary = create<LibraryState>()((set) => ({
  ...empty(),

  merge: (collection, records) =>
    set((s) => ({ [collection]: mergeTable(s[collection] as Table<SyncRecord>, records) }) as Partial<LibraryState>),

  applyChanges: (changes) =>
    set((s) => ({
      folders: mergeTable(s.folders, changes.folders ?? []),
      books: mergeTable(s.books, changes.books ?? []),
      progress: mergeTable(s.progress, changes.progress ?? []),
      annotations: mergeTable(s.annotations, changes.annotations ?? []),
      settings: mergeTable(s.settings, changes.settings ?? []),
      version: Math.max(s.version, changes.version),
      ready: true,
    })),

  reset: (snapshot) => set({ ...empty(), ...snapshot }),
}));

export const PERSISTED_KEYS = ["folders", "books", "progress", "annotations", "settings", "version"] as const;
