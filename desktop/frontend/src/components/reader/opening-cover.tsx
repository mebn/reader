import { useEffect, useState } from "react";
import { motion } from "motion/react";
import { BookCover } from "@/components/common/book-cover";
import type { Book } from "@/lib/types";
import { useBookTransition } from "@/store/transition";

const EASE = [0.32, 0.72, 0, 1] as const;

/** The cover flies from the library grid to the middle of the window, then dissolves into the page. */
export function OpeningCover({ book, ready }: { book: Book; ready: boolean }) {
  const [from] = useState(() => {
    const opening = useBookTransition.getState().opening;
    return opening?.bookId === book.id ? opening.rect : null;
  });
  const [done, setDone] = useState(!from);

  useEffect(() => () => useBookTransition.setState({ opening: null }), []);

  if (done || !from) return null;

  const height = Math.min(window.innerHeight * 0.6, 520);
  const width = (height * 2) / 3;
  const target = { left: (window.innerWidth - width) / 2, top: (window.innerHeight - height) / 2, width, height };

  return (
    <motion.div
      className="pointer-events-none fixed z-50"
      initial={{ left: from.left, top: from.top, width: from.width, height: from.height, opacity: 1 }}
      animate={ready ? { ...target, opacity: 0, scale: 1.06 } : { ...target, opacity: 1 }}
      transition={ready ? { duration: 0.35, ease: EASE } : { duration: 0.5, ease: EASE }}
      onAnimationComplete={() => ready && setDone(true)}
    >
      <BookCover book={book} className="aspect-auto h-full shadow-2xl" />
    </motion.div>
  );
}
