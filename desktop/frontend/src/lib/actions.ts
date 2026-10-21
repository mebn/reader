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
      const info = await readBookInfo(file, format, file.name);
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

export function updateAnnotation(annotation: Annotation, patch: Partial<Pick<Annotation, "note" | "color">>) {
  sync.put("annotations", { ...annotation, ...patch });
}

export function removeAnnotation(annotation: Annotation) {
  sync.put("annotations", { ...annotation, deleted: true });
}
