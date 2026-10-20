import type { ReactNode } from "react";
import { motion } from "motion/react";
import { Bookmark, ChevronLeft, List, Pin } from "lucide-react";
import { cn } from "@/lib/utils";

interface ReaderToolbarProps {
  visible: boolean;
  title: string;
  bookmarked: boolean;
  pinned: boolean;
  settings: ReactNode;
  onClose(): void;
  onContents(): void;
  onBookmark(): void;
  onPin(): void;
}

export function ChromeButton({ active, className, ...props }: React.ComponentProps<"button"> & { active?: boolean }) {
  return (
    <button
      type="button"
      className={cn(
        "inline-flex size-8 items-center justify-center rounded-md text-[color:var(--reader-fg)] opacity-55 transition hover:bg-[color:var(--reader-fg)]/8 hover:opacity-100 [&_svg]:size-[17px]",
        active && "opacity-100",
        className,
      )}
      {...props}
    />
  );
}

/** Auto-hiding top bar of the reader. */
export function ReaderToolbar({ visible, title, bookmarked, pinned, settings, onClose, onContents, onBookmark, onPin }: ReaderToolbarProps) {
  return (
    <motion.header
      initial={false}
      animate={{ opacity: visible ? 1 : 0, y: visible ? 0 : -6 }}
      transition={{ duration: 0.2 }}
      className={cn("drag-region traffic-light-inset absolute inset-x-0 top-0 z-30 flex h-12 items-center gap-1 px-3", !visible && "pointer-events-none")}
    >
      <ChromeButton onClick={onClose} aria-label="Close book">
        <ChevronLeft />
      </ChromeButton>
      <div className="pointer-events-none absolute inset-x-44 truncate text-center text-[13px] font-medium text-[color:var(--reader-fg)] opacity-60">{title}</div>
      <div className="ml-auto flex items-center gap-0.5">
        <ChromeButton onClick={onContents} aria-label="Contents and notes">
          <List />
        </ChromeButton>
        <ChromeButton onClick={onBookmark} active={bookmarked} aria-label="Bookmark">
          <Bookmark className={cn(bookmarked && "fill-current")} />
        </ChromeButton>
        {settings}
        <ChromeButton onClick={onPin} active={pinned} aria-label="Keep on top">
          <Pin className={cn("transition-transform", pinned && "rotate-45 fill-current")} />
        </ChromeButton>
      </div>
    </motion.header>
  );
}
