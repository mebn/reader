import type { Position } from "@/reader";

/** Chapter and page progress, centered under the text. */
export function ReaderFooter({ position }: { position: Position | null }) {
  if (!position) return null;
  const { chapter, chapterCount, page, pageCount } = position;

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-0 z-10 flex h-12 items-center justify-center gap-5 text-[11px] font-medium tracking-wide text-[color:var(--reader-fg)] tabular-nums opacity-45">
      {chapter !== null && chapterCount > 0 && (
        <span>
          {chapter + 1} / {chapterCount}
        </span>
      )}
      <span>{page !== null && pageCount !== null ? `${page} / ${pageCount}` : "…"}</span>
    </div>
  );
}
