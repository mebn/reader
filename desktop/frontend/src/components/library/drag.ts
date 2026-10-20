import { useState } from "react";
import { moveFolder, updateBook } from "@/lib/actions";
import { useLibrary } from "@/store/library";

/** Internal drag payloads for moving items between folders. */
const BOOK = "application/x-reader-book";
const FOLDER = "application/x-reader-folder";

export type DragItem = { kind: "book" | "folder"; id: string };

export function startDrag(e: React.DragEvent, item: DragItem) {
  e.dataTransfer.setData(item.kind === "book" ? BOOK : FOLDER, item.id);
  e.dataTransfer.effectAllowed = "move";
}

function readDrag(e: React.DragEvent): DragItem | null {
  const book = e.dataTransfer.getData(BOOK);
  if (book) return { kind: "book", id: book };
  const folder = e.dataTransfer.getData(FOLDER);
  return folder ? { kind: "folder", id: folder } : null;
}

function carriesItem(e: React.DragEvent) {
  return e.dataTransfer.types.includes(BOOK) || e.dataTransfer.types.includes(FOLDER);
}

/** Makes an element accept dragged books and folders. */
export function useDropTarget(onDrop: (item: DragItem) => void) {
  const [over, setOver] = useState(false);
  return {
    over,
    props: {
      onDragOver: (e: React.DragEvent) => {
        if (!carriesItem(e)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        setOver(true);
      },
      onDragLeave: () => setOver(false),
      onDrop: (e: React.DragEvent) => {
        setOver(false);
        const item = readDrag(e);
        if (!item) return;
        e.preventDefault();
        e.stopPropagation();
        onDrop(item);
      },
    },
  };
}

export function moveItem(item: DragItem, folderId: string | null) {
  const { books, folders } = useLibrary.getState();
  if (item.kind === "book" && books[item.id]) updateBook(books[item.id], { folderId });
  if (item.kind === "folder" && folders[item.id] && item.id !== folderId) moveFolder(folders[item.id], folderId);
}
