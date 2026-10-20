import { useEffect, useRef, useState } from "react";
import { motion } from "motion/react";
import { BookCover } from "@/components/common/book-cover";
import { ConfirmDialog } from "@/components/common/confirm-dialog";
import { NameDialog } from "@/components/common/name-dialog";
import { HoverCard, HoverCardContent, HoverCardTrigger } from "@/components/ui/hover-card";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuSeparator, ContextMenuTrigger } from "@/components/ui/context-menu";
import { useOpenBook } from "@/hooks/use-open-book";
import { deleteBook, updateBook } from "@/lib/actions";
import type { Book } from "@/lib/types";
import { useLibrary } from "@/store/library";
import { useBookTransition } from "@/store/transition";
import { BookDetails } from "./book-details";
import { dragSource } from "./drag";
import { MoveToMenu } from "./move-to-menu";

export function BookCard({ book }: { book: Book }) {
  const percent = useLibrary((s) => s.progress[book.id]?.percent ?? 0);
  const openBook = useOpenBook();
  const [renaming, setRenaming] = useState(false);
  const [deleting, setDeleting] = useState(false);
  // Pressing on the card (to open or drag it) dismisses the hover card until the pointer leaves.
  const [details, setDetails] = useState(false);
  const pressed = useRef(false);
  const drag = dragSource({ kind: "book", id: book.id });

  // Settle back into place after the book is closed. Declarative, so StrictMode's
  // remount restarts the animation instead of freezing it on its first frame.
  const [greet] = useState(() => useBookTransition.getState().closedId === book.id);
  useEffect(() => {
    if (greet) useBookTransition.getState().clear();
  }, [greet]);

  const open = (newWindow?: boolean) => openBook(book, { newWindow });

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
            <motion.div
              initial={greet ? { scale: 1.08, opacity: 0.4 } : false}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ duration: 0.45, ease: [0.32, 0.72, 0, 1] }}
            >
              <button
                type="button"
                onPointerDown={(e) => {
                  pressed.current = true;
                  setDetails(false);
                  drag.onPointerDown(e);
                }}
                onPointerLeave={() => (pressed.current = false)}
                onClick={() => open()}
                className="group block w-full text-left outline-none"
              >
                <HoverCard openDelay={600} closeDelay={80} open={details} onOpenChange={(open) => setDetails(open && !pressed.current)}>
                  <HoverCardTrigger asChild>
                    <div data-drag-image className="transition-transform duration-300 ease-out group-hover:-translate-y-1 group-focus-visible:ring-2 group-focus-visible:ring-ring rounded-md">
                      <BookCover book={book} className="group-hover:shadow-lg transition-shadow duration-300" />
                    </div>
                  </HoverCardTrigger>
                  <HoverCardContent side="right" align="start" sideOffset={12} className="w-64" onClick={(e) => e.stopPropagation()}>
                    <BookDetails book={book} />
                  </HoverCardContent>
                </HoverCard>
                <div className="mt-2.5 truncate text-[13px] font-medium leading-tight">{book.title}</div>
                <div className="mt-0.5 text-xs text-muted-foreground tabular-nums">{Math.round(percent * 100)}%</div>
              </button>
            </motion.div>
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
