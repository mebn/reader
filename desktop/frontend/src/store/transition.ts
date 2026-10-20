import { create } from "zustand";
import type { Locator } from "@/lib/types";

interface BookTransition {
  /** The book that was just closed, so its card can greet the user. */
  closedId: string | null;
  /** Where to open a book instead of its saved position, such as a highlight picked from the notes page. */
  jump: { bookId: string; locator: Locator } | null;
  close(bookId: string): void;
  clear(): void;
  jumpTo(bookId: string, locator: Locator): void;
  /** The jump target for a book, consumed so it applies only once. */
  takeJump(bookId: string): Locator | null;
}

export const useBookTransition = create<BookTransition>()((set, get) => ({
  closedId: null,
  jump: null,
  close: (bookId) => set({ closedId: bookId }),
  clear: () => set({ closedId: null }),
  jumpTo: (bookId, locator) => set({ jump: { bookId, locator } }),
  takeJump: (bookId) => {
    const { jump } = get();
    if (jump?.bookId !== bookId) return null;
    set({ jump: null });
    return jump.locator;
  },
}));
