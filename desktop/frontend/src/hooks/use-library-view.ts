import { useMemo } from "react";
import { useLibrary } from "@/store/library";
import { useUploads } from "@/store/uploads";
import type { Book, Folder } from "@/lib/types";

const byName = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

export interface LibraryView {
  folder: Folder | null;
  /** Ancestors from the root down to (and including) the current folder. */
  path: Folder[];
  folders: Folder[];
  books: Book[];
  /** Book count and a few covers per child folder. */
  folderBooks: Record<string, Book[]>;
}

export function useLibraryView(folderId: string | null): LibraryView {
  const folders = useLibrary((s) => s.folders);
  const stored = useLibrary((s) => s.books);
  const pending = useUploads((s) => s.pending);

  return useMemo(() => {
    const folder = folderId ? (folders[folderId] ?? null) : null;

    const path: Folder[] = [];
    for (let f: Folder | undefined = folder ?? undefined; f && path.length < 32; f = f.parentId ? folders[f.parentId] : undefined) path.unshift(f);

    const parent = folder?.id ?? null;
    const allBooks = Object.values({ ...pending, ...stored });
    const childFolders = Object.values(folders)
      .filter((f) => (f.parentId ?? null) === parent)
      .sort((a, b) => byName.compare(a.name, b.name));

    const folderBooks: Record<string, Book[]> = {};
    for (const f of childFolders) folderBooks[f.id] = allBooks.filter((b) => b.folderId === f.id).sort((a, b) => b.addedAt - a.addedAt);

    return {
      folder,
      path,
      folders: childFolders,
      books: allBooks.filter((b) => (b.folderId ?? null) === parent).sort((a, b) => b.addedAt - a.addedAt),
      folderBooks,
    };
  }, [folderId, folders, stored, pending]);
}
