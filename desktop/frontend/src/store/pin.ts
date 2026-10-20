import { create } from "zustand";
import { platform } from "@/platform";

/** Whether this window stays above other windows. Belongs to the window, not to a page. */
export const usePin = create<{ pinned: boolean; toggle(): Promise<void> }>()((set, get) => ({
  pinned: false,
  async toggle() {
    set({ pinned: await platform().setPinned(!get().pinned) });
  },
}));
