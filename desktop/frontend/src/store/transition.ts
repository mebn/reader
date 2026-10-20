import { create } from "zustand";

interface BookTransition {
  /** Where the cover of the book being opened was on screen. */
  opening: { bookId: string; rect: DOMRect } | null;
  /** The book that was just closed, so its card can greet the user. */
  closedId: string | null;
  open(bookId: string, rect: DOMRect): void;
  close(bookId: string): void;
  clear(): void;
}

export const useBookTransition = create<BookTransition>()((set) => ({
  opening: null,
  closedId: null,
  open: (bookId, rect) => set({ opening: { bookId, rect }, closedId: null }),
  close: (bookId) => set({ opening: null, closedId: bookId }),
  clear: () => set({ opening: null, closedId: null }),
}));
