import { useState } from "react";
import type { Book } from "@/lib/types";
import { cn } from "@/lib/utils";
import { platform } from "@/platform";
import { useSession } from "@/store/session";

const TINTS = ["#5b6b7a", "#7a5b5b", "#5b7a65", "#6d5b7a", "#7a6d5b", "#4f6f78", "#7a5b6f", "#62705a"];

function tint(seed: string) {
  let h = 0;
  for (const c of seed) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return TINTS[h % TINTS.length];
}

export function useCoverUrl(book: Book | undefined) {
  const session = useSession((s) => s.session);
  return book?.hasCover && session ? platform().coverUrl(book, session) : null;
}

/** A book's cover, or a typographic stand-in when it has none. */
export function BookCover({ book, className }: { book: Book; className?: string }) {
  const url = useCoverUrl(book);
  const [failed, setFailed] = useState(false);

  return (
    <div className={cn("relative aspect-[2/3] overflow-hidden rounded-md bg-muted shadow-sm ring-1 ring-black/5 dark:ring-white/5", className)}>
      {url && !failed ? (
        <img src={url} alt="" draggable={false} onError={() => setFailed(true)} className="size-full object-cover" />
      ) : (
        <div
          className="flex size-full flex-col justify-between p-[9%] text-white"
          style={{ background: `linear-gradient(160deg, ${tint(book.title)}, color-mix(in oklab, ${tint(book.title)} 65%, black))` }}
        >
          <div className="line-clamp-5 font-serif text-[clamp(11px,1.15vw,17px)] leading-tight font-medium">{book.title}</div>
          <div className="line-clamp-2 text-[clamp(9px,0.8vw,12px)] opacity-75">{book.author}</div>
        </div>
      )}
      <div className="pointer-events-none absolute inset-y-0 left-0 w-[5%] bg-gradient-to-r from-black/15 to-transparent" />
    </div>
  );
}
