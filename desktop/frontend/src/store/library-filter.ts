import { create } from "zustand";
import type { LibraryTab } from "@/lib/settings";

export type { LibraryTab };

/**
 * The library's tab and search, kept while a book is open so they're still there on
 * return. The tab is null until picked, so each launch starts on the default tab.
 */
export const useLibraryFilter = create<{
  tab: LibraryTab | null;
  query: string;
  setTab(tab: LibraryTab): void;
  setQuery(query: string): void;
}>()((set) => ({
  tab: null,
  query: "",
  setTab: (tab) => set({ tab }),
  setQuery: (query) => set({ query }),
}));
