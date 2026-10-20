import { useEffect, useRef, useState } from "react";
import { motion, useAnimate } from "motion/react";
import { BookCover } from "@/components/common/book-cover";
import { ConfirmDialog } from "@/components/common/confirm-dialog";
import { NameDialog } from "@/components/common/name-dialog";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuSeparator, ContextMenuTrigger } from "@/components/ui/context-menu";
import { useOpenBook } from "@/hooks/use-open-book";
import { deleteBook, updateBook } from "@/lib/actions";
import type { Book } from "@/lib/types";
import { useLibrary } from "@/store/library";
import { useBookTransition } from "@/store/transition";
import { startDrag } from "./drag";
import { MoveToMenu } from "./move-to-menu";

export function BookCard({ book }: { book: Book }) {
  const percent = useLibrary((s) => s.progress[book.id]?.percent ?? 0);
  const openBook = useOpenBook();
  const coverRef = useRef<HTMLDivElement>(null);
  const [scope, animate] = useAnimate();
  const [renaming, setRenaming] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // Settle back into place after the book is closed.
  useEffect(() => {
    const { closedId, clear } = useBookTransition.getState();
    if (closedId !== book.id) return;
    clear();
    void animate(scope.current, { scale: [1.08, 1], opacity: [0.4, 1] }, { duration: 0.45, ease: [0.32, 0.72, 0, 1] });
  }, [animate, book.id, scope]);

  const open = (newWindow?: boolean) => openBook(book, { rect: coverRef.current?.getBoundingClientRect(), newWindow });

  return (
    <>
      <ContextMenu>
        <ContextMenuTrigger asChild>
          <motion.div
            layout
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9 }}
            transition={{ duration: 0.3, ease: [0.32, 0.72, 0, 1] }}
          >
            <button
              ref={scope}
              type="button"
              draggable
              onDragStart={(e) => startDrag(e, { kind: "book", id: book.id })}
              onClick={() => open()}
              className="group block w-full text-left outline-none"
            >
              <div ref={coverRef} className="transition-transform duration-300 ease-out group-hover:-translate-y-1 group-focus-visible:ring-2 group-focus-visible:ring-ring rounded-md">
                <BookCover book={book} className="group-hover:shadow-lg transition-shadow duration-300" />
              </div>
              <div className="mt-2.5 truncate text-[13px] font-medium leading-tight">{book.title}</div>
              <div className="mt-0.5 text-xs text-muted-foreground tabular-nums">{Math.round(percent * 100)}%</div>
            </button>
          </motion.div>
        </ContextMenuTrigger>
        <ContextMenuContent className="w-48">
          <ContextMenuItem onSelect={() => open(false)}>Open</ContextMenuItem>
          <ContextMenuItem onSelect={() => open(true)}>Open in new window</ContextMenuItem>
          <ContextMenuSeparator />
          <ContextMenuItem onSelect={() => setRenaming(true)}>Rename</ContextMenuItem>
          <MoveToMenu current={book.folderId} onMove={(folderId) => updateBook(book, { folderId })} />
          <ContextMenuSeparator />
          <ContextMenuItem variant="destructive" onSelect={() => setDeleting(true)}>
            Delete
          </ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>

      <NameDialog open={renaming} onOpenChange={setRenaming} title="Rename book" initial={book.title} action="Save" onSubmit={(title) => updateBook(book, { title })} />
      <ConfirmDialog
        open={deleting}
        onOpenChange={setDeleting}
        title={`Delete “${book.title}”?`}
        description="It will be removed from all your devices, with its notes and highlights."
        action="Delete"
        onConfirm={() => deleteBook(book)}
      />
    </>
  );
}
