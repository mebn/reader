import { ChevronLeft } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import type { ReaderSettings } from "@/lib/settings";
import { cn } from "@/lib/utils";
import type { Position } from "@/reader";

const LINE = "pointer-events-none absolute inset-x-0 z-10 flex h-12 items-center justify-center gap-5 px-24 text-[11px] font-medium tracking-wide text-[color:var(--reader-fg)] tabular-nums";

/** Whatever the settings ask for, centered under the text. */
export function ReaderFooter({ position, chapter, settings }: { position: Position | null; chapter: string | undefined; settings: ReaderSettings }) {
  if (!position) return null;
  const { chapterPage, chapterPageCount, page, pageCount, percent } = position;

  const parts = [
    settings.footerChapter && chapter && <span className="min-w-0 truncate">{chapter}</span>,
    settings.footerChapterPages && chapterPage !== null && chapterPageCount !== null && (
      <span className="shrink-0">
        {chapterPage} / {chapterPageCount} in chapter
      </span>
    ),
    settings.footerBookPages && <span className="shrink-0">{page !== null && pageCount !== null ? `${page} / ${pageCount}` : "…"}</span>,
    settings.footerPercent && <span className="shrink-0">{Math.round(percent * 100)}%</span>,
  ].filter(Boolean);

  if (!parts.length) return null;
  return (
    // Separated by dots, like the header.
    <div className={cn(LINE, "bottom-0 gap-1.5 opacity-45")}>
      {parts.map((part, i) => (
        <span key={i} className="contents">
          {i > 0 && <span aria-hidden>·</span>}
          {part}
        </span>
      ))}
    </div>
  );
}

/** The running line above the text: the book or chapter title, out of the way of the toolbar. */
export function ReaderHeader({ text, hidden }: { text: string | undefined; hidden: boolean }) {
  if (!text) return null;
  return (
    <motion.div initial={false} animate={{ opacity: hidden ? 0 : 0.45 }} transition={{ duration: 0.2 }} className={`${LINE} top-0 h-(--titlebar-height)`}>
      <span className="truncate">{text}</span>
    </motion.div>
  );
}

const CORNER =
  "pointer-events-auto flex h-8 items-center gap-1 rounded-md px-2 text-[11px] font-medium tracking-wide text-(--reader-fg)/55 transition-colors hover:text-(--reader-fg) focus-visible:text-(--reader-fg) focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-(--reader-fg)/30";

/**
 * The way back to where reading was before going to a highlight, note or bookmark, in the
 * bottom left, and the offer to continue where another device got to in the bottom right.
 */
export function ReaderJumps({ back, offer, onBack, onContinue }: { back: string | null; offer: string | null; onBack(): void; onContinue(): void }) {
  const fade = { initial: { opacity: 0 }, animate: { opacity: 1 }, exit: { opacity: 0 }, transition: { duration: 0.15 } };
  return (
    <>
      <div className="pointer-events-none absolute bottom-2 left-3 z-20 flex items-center">
        <AnimatePresence initial={false}>
          {back && (
            <motion.button key="back" type="button" className={CORNER} onClick={onBack} {...fade}>
              <ChevronLeft className="size-3.5" />
              {back}
            </motion.button>
          )}
        </AnimatePresence>
      </div>
      <div className="pointer-events-none absolute right-3 bottom-2 z-20 flex items-center">
        <AnimatePresence initial={false}>
          {offer && (
            <motion.button key="offer" type="button" className={CORNER} onClick={onContinue} title="You read further on another device" {...fade}>
              {offer}
            </motion.button>
          )}
        </AnimatePresence>
      </div>
    </>
  );
}
