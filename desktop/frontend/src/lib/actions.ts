import { toast } from "sonner";
import { useLibrary } from "@/store/library";
import { useSession } from "@/store/session";
import { useUploads } from "@/store/uploads";
import { readBookInfo } from "@/reader/formats";
import { api } from "./api";
import { sync } from "./sync";
import { formatFromName, type Annotation, type Book, type Folder, type Locator } from "./types";

const COVER_WIDTH = 600;

// Folders

export function createFolder(name: string, parentId: string | null) {
  return sync.put<Folder>("folders", { id: crypto.randomUUID(), modifiedAt: 0, name, parentId });
}

export function renameFolder(folder: Folder, name: string) {
  sync.put("folders", { ...folder, name });
}

export function moveFolder(folder: Folder, parentId: string | null) {
  if (folder.id !== parentId) sync.put("folders", { ...folder, parentId });
}

export function deleteFolder(folder: Folder) {
  sync.deleteFolder(folder.id);
}

// Books

export function updateBook(book: Book, patch: Partial<Pick<Book, "title" | "author" | "folderId">>) {
  sync.put("books", { ...book, ...patch });
}

export function deleteBook(book: Book) {
  sync.put("books", { ...book, deleted: true });
}

/** Parses, uploads and adds books. Unsupported files are skipped with a notice. */
export async function importFiles(files: File[], folderId: string | null) {
  const session = useSession.getState().session;
  if (!session) return;

  const supported = files.filter((f) => formatFromName(f.name));
  const skipped = files.length - supported.length;
  if (skipped) toast(`${skipped} file${skipped > 1 ? "s" : ""} skipped`, { description: "Supported: EPUB, PDF, FB2, CBZ, TXT" });
  if (!supported.length) return;

  const id = toast.loading(supported.length > 1 ? `Adding ${supported.length} books` : `Adding ${supported[0].name}`);
  let added = 0;
  let pending: string | null = null;
  for (const file of supported) {
    try {
      const format = formatFromName(file.name)!;
      // The parsers' own errors (such as a zip library's) mean nothing to people.
      const info = await readBookInfo(file, format, file.name).catch((err) => {
        console.error(err);
        throw new Error(`It can't be read as ${format.toUpperCase()}; the file may be damaged.`);
      });
      const book: Book = {
        id: crypto.randomUUID(),
        modifiedAt: Date.now(),
        folderId,
        title: info.title || file.name,
        author: info.author,
        format,
        fileName: file.name,
        size: file.size,
        hash: "",
        hasCover: Boolean(info.cover),
        addedAt: Date.now(),
      };
      const cover = info.cover ? await shrinkImage(info.cover).catch(() => info.cover!) : undefined;
      // The card shows up right away, with a spinner, and can't be opened until the server has the file.
      pending = book.id;
      useUploads.getState().start(book);
      sync.received("books", await api.uploadBook(session, book, file, cover));
      useUploads.getState().finish(book.id);
      pending = null;
      added++;
    } catch (err) {
      if (pending) useUploads.getState().finish(pending);
      pending = null;
      console.error(err);
      toast.error(`Couldn't add ${file.name}`, { description: (err as Error).message });
    }
  }
  if (added) toast.success(added > 1 ? `Added ${added} books` : "Book added", { id });
  else toast.dismiss(id);
}

async function shrinkImage(blob: Blob): Promise<Blob> {
  const bitmap = await createImageBitmap(blob);
  if (bitmap.width <= COVER_WIDTH) return blob;
  const canvas = document.createElement("canvas");
  canvas.width = COVER_WIDTH;
  canvas.height = Math.round((bitmap.height / bitmap.width) * COVER_WIDTH);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject()), "image/jpeg", 0.86));
}

// Reading

export function saveProgress(bookId: string, locator: Locator, percent: number) {
  const existing = useLibrary.getState().progress[bookId];
  sync.put("progress", { id: bookId, modifiedAt: existing?.modifiedAt ?? 0, locator: JSON.stringify(locator), percent });
}

export function addAnnotation(annotation: Omit<Annotation, "id" | "modifiedAt">) {
  return sync.put<Annotation>("annotations", { ...annotation, id: crypto.randomUUID(), modifiedAt: 0 });
}

export function updateAnnotation(annotation: Annotation, patch: Partial<Pick<Annotation, "note" | "color" | "locator" | "text">>) {
  sync.put("annotations", { ...annotation, ...patch });
}

/**
 * Highlights a selection. One that overlaps highlights already there grows the newest of
 * them to cover it all, keeping its color and every note, instead of piling another on top.
 * `textOf` gives the text of the combined range.
 */
export function highlightSelection(
  bookId: string,
  existing: Annotation[],
  selection: { locator: Locator; text: string },
  color: string,
  textOf: (locator: Locator) => string | null,
): Annotation {
  const { locator } = selection;
  const overlapping = existing
    .filter((a) => a.kind === "highlight" && !a.deleted)
    .filter((a) => {
      const l = JSON.parse(a.locator) as Locator;
      return l.chapter === locator.chapter && l.page === locator.page && l.start !== undefined && l.end !== undefined && l.start < locator.end! && locator.start! < l.end;
    })
    .sort((a, b) => b.modifiedAt - a.modifiedAt);
  if (!overlapping.length || locator.start === undefined || locator.end === undefined) {
    return addAnnotation({ bookId, kind: "highlight", locator: JSON.stringify(locator), text: selection.text, note: "", color, label: "" });
  }
  const ranges = [locator, ...overlapping.map((a) => JSON.parse(a.locator) as Locator)];
  const merged = { ...locator, start: Math.min(...ranges.map((l) => l.start!)), end: Math.max(...ranges.map((l) => l.end!)) };
  const [keep, ...rest] = overlapping;
  const note = overlapping.map((a) => a.note.trim()).filter(Boolean).join("\n\n");
  const updated = { ...keep, locator: JSON.stringify(merged), text: textOf(merged) ?? selection.text, note };
  sync.put("annotations", updated);
  rest.forEach(removeAnnotation);
  return updated;
}

export function removeAnnotation(annotation: Annotation) {
  sync.put("annotations", { ...annotation, deleted: true });
}
