export const FORMATS = ["epub", "pdf", "fb2", "cbz", "txt"] as const;
export type Format = (typeof FORMATS)[number];

export interface SyncRecord {
  id: string;
  modifiedAt: number;
  version?: number;
  deleted?: boolean;
}

export interface Folder extends SyncRecord {
  name: string;
  parentId: string | null;
}

export interface Book extends SyncRecord {
  folderId: string | null;
  title: string;
  author: string;
  format: Format;
  fileName: string;
  size: number;
  hash: string;
  hasCover: boolean;
  addedAt: number;
}

/** Progress uses the book ID as its ID. `locator` is a serialized {@link Locator}. */
export interface Progress extends SyncRecord {
  locator: string;
  percent: number;
}

export type AnnotationKind = "highlight" | "bookmark";

export interface Annotation extends SyncRecord {
  bookId: string;
  kind: AnnotationKind;
  locator: string;
  text: string;
  note: string;
  color: string;
  label: string;
}

/** Settings use their scope as ID: "app", "reader" or "reader:<bookId>". */
export interface Setting extends SyncRecord {
  data: string;
}

export interface Changes {
  version: number;
  folders: Folder[];
  books: Book[];
  progress: Progress[];
  annotations: Annotation[];
  settings: Setting[];
}

export type Collection = Exclude<keyof Changes, "version">;

export interface User {
  id: string;
  email: string;
}

/**
 * A position in a book. Reflowable books use chapter + fraction so positions survive
 * font and window changes; fixed layouts use the page. Text ranges add character offsets.
 */
export interface Locator {
  chapter?: number;
  fraction?: number;
  page?: number;
  start?: number;
  end?: number;
}

export function formatFromName(name: string): Format | null {
  const ext = name.split(".").pop()?.toLowerCase();
  return (FORMATS as readonly string[]).includes(ext ?? "") ? (ext as Format) : null;
}
