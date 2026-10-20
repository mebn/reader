import { useLayoutEffect, useSyncExternalStore } from "react";
import { create } from "zustand";
import { resolveDark, type ThemeMode } from "@/lib/settings";
import { useAppSettings } from "./use-settings";

/** Lets an open book temporarily drive the window theme. */
export const useThemeOverride = create<{ mode: ThemeMode | null; set(mode: ThemeMode | null): void }>()((set) => ({
  mode: null,
  set: (mode) => set({ mode }),
}));

const media = matchMedia("(prefers-color-scheme: dark)");
const subscribe = (cb: () => void) => {
  media.addEventListener("change", cb);
  return () => media.removeEventListener("change", cb);
};

export function useIsDark(mode: ThemeMode) {
  const systemDark = useSyncExternalStore(subscribe, () => media.matches);
  return mode === "system" ? systemDark : resolveDark(mode);
}

/** Applies the effective theme to the document. */
export function useApplyTheme() {
  const [app] = useAppSettings();
  const override = useThemeOverride((s) => s.mode);
  const dark = useIsDark(override ?? app.theme);

  // Before paint, so the whole window switches in the same frame.
  useLayoutEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    document.documentElement.style.colorScheme = dark ? "dark" : "light";
  }, [dark]);

  return dark;
}
