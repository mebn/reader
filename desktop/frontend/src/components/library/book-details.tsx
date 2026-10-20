import { useMemo } from "react";
import type { Book } from "@/lib/types";
import { useLibrary } from "@/store/library";

const dateFormat = new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short", year: "numeric" });
const relative = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

function formatSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

/** "today", "yesterday", "3 days ago", then a date. */
export function formatWhen(at: number) {
  const days = Math.round((startOfDay(at) - startOfDay(Date.now())) / 86_400_000);
  return days > -7 ? relative.format(days, "day") : dateFormat.format(at);
}

function startOfDay(at: number) {
  const d = new Date(at);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/** Everything known about a book, for its hover card in the library. */
export function BookDetails({ book }: { book: Book }) {
  const progress = useLibrary((s) => s.progress[book.id]);
  const folder = useLibrary((s) => (book.folderId ? s.folders[book.folderId] : undefined));
  const annotations = useLibrary((s) => s.annotations);
  const counts = useMemo(() => {
    const mine = Object.values(annotations).filter((a) => a.bookId === book.id && !a.deleted);
    return {
      highlights: mine.filter((a) => a.kind === "highlight").length,
      notes: mine.filter((a) => a.kind === "highlight" && a.note.trim()).length,
      bookmarks: mine.filter((a) => a.kind === "bookmark").length,
    };
  }, [annotations, book.id]);

  const percent = Math.round((progress?.percent ?? 0) * 100);
  const marks = [
    counts.highlights && `${counts.highlights} ${counts.highlights === 1 ? "highlight" : "highlights"}`,
    counts.notes && `${counts.notes} ${counts.notes === 1 ? "note" : "notes"}`,
    counts.bookmarks && `${counts.bookmarks} ${counts.bookmarks === 1 ? "bookmark" : "bookmarks"}`,
  ].filter(Boolean);

  return (
    <div className="grid gap-3">
      <div>
        <div className="text-sm leading-snug font-semibold">{book.title}</div>
        {book.author && <div className="mt-0.5 text-[13px] text-muted-foreground">{book.author}</div>}
      </div>

      <div>
        <div className="mb-1.5 flex justify-between text-xs text-muted-foreground tabular-nums">
          <span>{percent === 0 ? "Not started" : percent >= 100 ? "Finished" : `${percent}% read`}</span>
          {progress && percent > 0 && <span>{formatWhen(progress.modifiedAt)}</span>}
        </div>
        <div className="h-1 overflow-hidden rounded-full bg-muted">
          <div className="h-full rounded-full bg-foreground/70" style={{ width: `${percent}%` }} />
        </div>
      </div>

      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-xs">
        {marks.length > 0 && (
          <>
            <dt className="text-muted-foreground">Notes</dt>
            <dd>{marks.join(" · ")}</dd>
          </>
        )}
        {folder && (
          <>
            <dt className="text-muted-foreground">Folder</dt>
            <dd className="truncate">{folder.name}</dd>
          </>
        )}
        <dt className="text-muted-foreground">Format</dt>
        <dd>
          {book.format.toUpperCase()} · {formatSize(book.size)}
        </dd>
        <dt className="text-muted-foreground">Added</dt>
        <dd>{dateFormat.format(book.addedAt)}</dd>
      </dl>
    </div>
  );
}
