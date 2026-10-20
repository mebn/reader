import { useMemo } from "react";
import { Bookmark } from "lucide-react";
import { motion } from "motion/react";
import { BookCover } from "@/components/common/book-cover";
import { useOpenBook } from "@/hooks/use-open-book";
import { removeAnnotation } from "@/lib/actions";
import type { Annotation, Book, Locator } from "@/lib/types";
import { HIGHLIGHT_COLORS } from "@/reader/text-ranges";
import { useLibrary } from "@/store/library";
import { useBookTransition } from "@/store/transition";

/** "plain" is highlights without a note, for when notes are listed on their own. */
export type AnnotationFilter = "all" | "highlights" | "plain" | "notes" | "bookmarks";

export interface AnnotationGroup {
  book: Book;
  list: Annotation[];
}

function matches(a: Annotation, filter: AnnotationFilter, query: string) {
  if (filter === "highlights" && a.kind !== "highlight") return false;
  if (filter === "plain" && (a.kind !== "highlight" || a.note.trim())) return false;
  if (filter === "notes" && !a.note.trim()) return false;
  if (filter === "bookmarks" && a.kind !== "bookmark") return false;
  if (!query) return true;
  return [a.text, a.note, a.label].some((s) => s.toLowerCase().includes(query));
}

function locationKey(a: Annotation) {
  const l = JSON.parse(a.locator) as Locator;
  return (l.chapter ?? l.page ?? 0) * 1e7 + (l.start ?? (l.fraction ?? 0) * 1e6);
}

/** Highlights, notes and bookmarks of some books, grouped by book, most recently touched first. */
export function useAnnotationGroups(filter: AnnotationFilter, query: string, inScope: (book: Book) => boolean): AnnotationGroup[] {
  const books = useLibrary((s) => s.books);
  const annotations = useLibrary((s) => s.annotations);

  return useMemo(() => {
    const q = query.trim().toLowerCase();
    const byBook = new Map<string, Annotation[]>();
    for (const a of Object.values(annotations)) {
      const book = books[a.bookId];
      if (a.deleted || !book || book.deleted || !inScope(book) || !matches(a, filter, q)) continue;
      byBook.set(a.bookId, [...(byBook.get(a.bookId) ?? []), a]);
    }
    return [...byBook.entries()]
      .map(([bookId, list]) => ({ book: books[bookId], list: list.sort((a, b) => locationKey(a) - locationKey(b)) }))
      .sort((a, b) => Math.max(...b.list.map((x) => x.modifiedAt)) - Math.max(...a.list.map((x) => x.modifiedAt)));
  }, [annotations, books, filter, query, inScope]);
}

/** Annotation groups; clicking one opens its book at that spot. */
export function AnnotationList({ groups }: { groups: AnnotationGroup[] }) {
  const openBook = useOpenBook();
  const go = (book: Book, a: Annotation) => {
    useBookTransition.getState().jumpTo(book.id, JSON.parse(a.locator) as Locator);
    openBook(book, { newWindow: false });
  };

  return (
    <div className="grid max-w-3xl gap-10">
      {groups.map(({ book, list }) => (
        <motion.section key={book.id} layout="position" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25 }}>
          <div className="mb-3 flex items-center gap-3">
            <BookCover book={book} className="w-9 shrink-0 rounded-sm" />
            <div className="min-w-0">
              <div className="truncate text-sm font-medium">{book.title}</div>
              <div className="truncate text-xs text-muted-foreground">
                {book.author ? `${book.author} · ` : ""}
                {list.length} {list.length === 1 ? "item" : "items"}
              </div>
            </div>
          </div>
          <ul className="grid gap-1">
            {list.map((a) => (
              <li key={a.id} className="group relative">
                <button type="button" onClick={() => go(book, a)} className="w-full rounded-md px-3 py-2.5 pr-8 text-left transition-colors hover:bg-accent">
                  {a.kind === "bookmark" ? (
                    <div className="flex items-start gap-2.5">
                      <Bookmark className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
                      <div className="min-w-0">
                        <div className="truncate text-sm">{a.label}</div>
                        {a.text && <div className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{a.text}</div>}
                      </div>
                    </div>
                  ) : (
                    <>
                      <p className="line-clamp-4 border-l-2 pl-2.5 font-serif text-[14px] leading-snug" style={{ borderColor: HIGHLIGHT_COLORS[a.color] }}>
                        {a.text}
                      </p>
                      {a.note && <p className="mt-1.5 line-clamp-4 pl-3 text-xs text-muted-foreground">{a.note}</p>}
                    </>
                  )}
                </button>
                <button
                  type="button"
                  onClick={() => removeAnnotation(a)}
                  aria-label="Remove"
                  className="absolute top-2 right-2 rounded px-1.5 text-xs text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 hover:text-destructive"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        </motion.section>
      ))}
    </div>
  );
}
