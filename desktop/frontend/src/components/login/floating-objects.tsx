import type { ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";
import { BOOKS, Bookmark, BookStack, ClosedBook, Cup, Glasses, OpenBook, Page, Pencil } from "./art";

interface Item {
  art: ReactNode;
  /** Position and width, as classes. */
  at: string;
  rotate: number;
  /** Sits behind the text, so it drops out in narrow windows. */
  middle?: boolean;
}

const ITEMS: Item[] = [
  { art: <ClosedBook {...BOOKS.clay} />, at: "left-[5%] top-[13%] w-[84px]", rotate: -14 },
  { art: <BookStack />, at: "left-[2%] top-[46%] w-[124px]", rotate: 6 },
  { art: <Glasses />, at: "left-[9%] top-[78%] w-[96px]", rotate: -8 },
  { art: <Pencil />, at: "left-[24%] top-[26%] w-[26px]", rotate: 28, middle: true },
  { art: <ClosedBook {...BOOKS.mustard} />, at: "left-[19%] top-[88%] w-[54px]", rotate: 12, middle: true },

  { art: <OpenBook />, at: "right-[5%] top-[9%] w-[142px]", rotate: 9 },
  { art: <Cup />, at: "right-[3%] top-[44%] w-[84px]", rotate: -6 },
  { art: <ClosedBook {...BOOKS.ink} />, at: "right-[9%] top-[70%] w-[78px]", rotate: 16 },
  { art: <ClosedBook {...BOOKS.sage} />, at: "right-[26%] top-[24%] w-[46px]", rotate: -18, middle: true },
  { art: <Page />, at: "right-[20%] top-[88%] w-[58px]", rotate: 10, middle: true },
  { art: <Bookmark />, at: "left-[42%] top-[-2%] w-[22px]", rotate: 0, middle: true },
  { art: <ClosedBook {...BOOKS.plum} />, at: "left-[14%] top-[34%] w-[40px]", rotate: -26, middle: true },
];

/** Books and bookish things that pop into place one after another, then stay put. */
export function FloatingObjects() {
  const calm = useReducedMotion();
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
      {ITEMS.map((item, i) => (
        <div key={i} className={`absolute ${item.at} ${item.middle ? "max-[760px]:hidden" : "max-[560px]:opacity-40"}`}>
          <motion.div
            initial={calm ? false : { opacity: 0, scale: 0.4, rotate: item.rotate - 30 }}
            animate={{ opacity: 1, scale: 1, rotate: item.rotate }}
            transition={{ delay: 0.15 + i * 0.07, type: "spring", stiffness: 120, damping: 14 }}
          >
            {item.art}
          </motion.div>
        </div>
      ))}
    </div>
  );
}
