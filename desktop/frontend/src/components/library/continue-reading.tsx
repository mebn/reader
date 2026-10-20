import { useMemo } from "react";
import { motion } from "motion/react";
import { BookCover, useCoverUrl } from "@/components/common/book-cover";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuTrigger } from "@/components/ui/context-menu";
import { useOpenBook } from "@/hooks/use-open-book";
import type { Book } from "@/lib/types";
import { useLibrary } from "@/store/library";
import { formatWhen } from "./book-details";

/** The unfinished book read most recently among some books, if any. */
export function useLastRead(inScope: (book: Book) => boolean) {
  const books = useLibrary((s) => s.books);
  const progress = useLibrary((s) => s.progress);
  return useMemo(() => {
    let best: { book: Book; percent: number; at: number } | null = null;
    for (const p of Object.values(progress)) {
      const book = books[p.id];
      if (!book || book.deleted || p.deleted || p.percent <= 0 || p.percent >= 0.995 || !inScope(book)) continue;
      if (!best || p.modifiedAt > best.at) best = { book, percent: p.percent, at: p.modifiedAt };
    }
    return best;
  }, [books, progress, inScope]);
}

/** A wide card for picking up where you left off, set on a soft wash of the book's own cover. */
export function ContinueReading({ book, percent, at }: { book: Book; percent: number; at: number }) {
  const openBook = useOpenBook();
  const cover = useCoverUrl(book);
  const shown = Math.round(percent * 100);

  return (
    <ContextMenu>
      <ContextMenuTrigger asChild>
        <motion.button
          type="button"
          onClick={() => openBook(book)}
          aria-label={`Continue reading ${book.title}`}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.35, ease: [0.32, 0.72, 0, 1] }}
          className="group relative isolate block w-full overflow-hidden rounded-2xl text-left ring-1 ring-black/5 transition-shadow duration-300 outline-none hover:shadow-lg focus-visible:ring-2 focus-visible:ring-ring dark:ring-white/10"
        >
          {cover && <img src={cover} alt="" aria-hidden className="absolute inset-0 -z-10 size-full scale-125 object-cover opacity-60 blur-3xl saturate-150" />}
          <div className="absolute inset-0 -z-10 bg-gradient-to-r from-background/70 via-background/80 to-background/95" />

          <div className="flex items-center gap-7 p-6 sm:p-7">
            <div className="w-24 shrink-0 sm:w-28">
              <BookCover book={book} className="shadow-xl" />
            </div>

            <div className="min-w-0 flex-1">
              <div className="text-[11px] font-semibold tracking-[0.14em] text-muted-foreground uppercase">Continue reading</div>
              <div className="mt-1.5 line-clamp-2 font-serif text-2xl leading-tight tracking-tight" style={{ fontFamily: '"Literata Variable", Georgia, serif' }}>
                {book.title}
              </div>
              {book.author && <div className="mt-1 truncate text-sm text-muted-foreground">{book.author}</div>}

              <div className="mt-4 flex max-w-sm items-center gap-3">
                <div className="h-1 flex-1 overflow-hidden rounded-full bg-foreground/10">
                  <div className="h-full rounded-full bg-foreground/70" style={{ width: `${shown}%` }} />
                </div>
                <span className="shrink-0 text-xs text-muted-foreground tabular-nums">{shown}%</span>
              </div>
              <div className="mt-1.5 text-xs text-muted-foreground">Last read {formatWhen(at)}</div>
            </div>
          </div>
        </motion.button>
      </ContextMenuTrigger>
      <ContextMenuContent className="w-48">
        <ContextMenuItem onSelect={() => openBook(book, { newWindow: false })}>Open</ContextMenuItem>
        <ContextMenuItem onSelect={() => openBook(book, { newWindow: true })}>Open in new window</ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  );
}
