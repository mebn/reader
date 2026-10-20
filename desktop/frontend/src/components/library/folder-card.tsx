import { useState } from "react";
import { motion } from "motion/react";
import { useLocation } from "wouter";
import { BookCover } from "@/components/common/book-cover";
import { ConfirmDialog } from "@/components/common/confirm-dialog";
import { NameDialog } from "@/components/common/name-dialog";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuSeparator, ContextMenuTrigger } from "@/components/ui/context-menu";
import { deleteFolder, moveFolder, renameFolder } from "@/lib/actions";
import type { Book, Folder } from "@/lib/types";
import { cn } from "@/lib/utils";
import { dragSource, moveItem, useDropTarget } from "./drag";
import { MoveToMenu } from "./move-to-menu";

/** Up to three covers fanned out like a small stack. */
const FAN = [
  { rotate: -7, x: "-14%", z: 1 },
  { rotate: 6, x: "14%", z: 2 },
  { rotate: 0, x: "0%", z: 3 },
];

export function FolderCard({ folder, books }: { folder: Folder; books: Book[] }) {
  const [, navigate] = useLocation();
  const [renaming, setRenaming] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const drop = useDropTarget((item) => moveItem(item, folder.id));
  const stack = books.slice(0, 3).reverse();

  return (
    <>
      <ContextMenu>
        <ContextMenuTrigger asChild>
          <motion.div layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, scale: 0.9 }} transition={{ duration: 0.3 }}>
            <button
              type="button"
              {...dragSource({ kind: "folder", id: folder.id })}
              onClick={() => navigate(`/folder/${folder.id}`)}
              className="group block w-full text-left outline-none"
              {...drop.props}
            >
              <div
                data-drag-image
                className={cn(
                  "relative flex aspect-[2/3] items-center justify-center overflow-hidden rounded-md bg-muted/70 ring-1 ring-black/5 transition-all duration-300 group-hover:-translate-y-1 group-hover:bg-muted dark:ring-white/5",
                  drop.over && "scale-[1.03] bg-accent ring-2 ring-ring",
                )}
              >
                {stack.map((book, i) => {
                  const fan = FAN[FAN.length - stack.length + i];
                  return (
                    <div
                      key={book.id}
                      className="absolute w-[52%] transition-transform duration-300 group-hover:scale-105"
                      style={{ transform: `translateX(${fan.x}) rotate(${fan.rotate}deg)`, zIndex: fan.z }}
                    >
                      <BookCover book={book} className="shadow-md" />
                    </div>
                  );
                })}
              </div>
              <div className="mt-2.5 truncate text-[13px] font-medium leading-tight">{folder.name}</div>
              <div className="mt-0.5 text-xs text-muted-foreground tabular-nums">{books.length}</div>
            </button>
          </motion.div>
        </ContextMenuTrigger>
        <ContextMenuContent className="w-48">
          <ContextMenuItem onSelect={() => setRenaming(true)}>Rename</ContextMenuItem>
          <MoveToMenu current={folder.parentId} exclude={folder.id} onMove={(parentId) => moveFolder(folder, parentId)} />
          <ContextMenuSeparator />
          <ContextMenuItem variant="destructive" onSelect={() => setDeleting(true)}>
            Delete
          </ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>

      <NameDialog open={renaming} onOpenChange={setRenaming} title="Rename folder" initial={folder.name} action="Save" onSubmit={(name) => renameFolder(folder, name)} />
      <ConfirmDialog
        open={deleting}
        onOpenChange={setDeleting}
        title={`Delete “${folder.name}”?`}
        description="Books inside are kept and moved up one level."
        action="Delete"
        onConfirm={() => deleteFolder(folder)}
      />
    </>
  );
}
