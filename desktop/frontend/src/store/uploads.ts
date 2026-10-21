import { create } from "zustand";
import type { Book } from "@/lib/types";

interface Uploads {
  /** Books being added, shown in the library until the server has their file. */
  pending: Record<string, Book>;
  start(book: Book): void;
  finish(id: string): void;
}

export const useUploads = create<Uploads>()((set) => ({
  pending: {},
  start: (book) => set((s) => ({ pending: { ...s.pending, [book.id]: book } })),
  finish: (id) =>
    set((s) => {
      const { [id]: _, ...pending } = s.pending;
      return { pending };
    }),
}));
