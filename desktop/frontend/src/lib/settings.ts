export type ThemeMode = "light" | "dark" | "system";

export interface ReaderSettings {
  theme: ThemeMode;
  /** A background id, or "auto" to follow the theme. */
  background: string;
  font: string;
  fontSize: number;
  lineHeight: number;
  weight: number;
  tracking: number;
  paragraphSpacing: number;
  margin: number;
  align: "left" | "justify";
  hyphenate: boolean;
  pages: 1 | 2;
}

export interface AppSettings {
  openInNewWindow: boolean;
}

export const DEFAULT_READER: ReaderSettings = {
  theme: "system",
  background: "auto",
  font: "literata",
  fontSize: 19,
  lineHeight: 1.6,
  weight: 400,
  tracking: 0,
  paragraphSpacing: 0.6,
  margin: 56,
  align: "justify",
  hyphenate: true,
  pages: 1,
};

export const DEFAULT_APP: AppSettings = { openInNewWindow: false };

export const SCOPE = {
  app: "app",
  reader: "reader",
  book: (bookId: string) => `reader:${bookId}`,
};

export interface Background {
  id: string;
  color: string;
  text: string;
  dark: boolean;
}

export const BACKGROUNDS: Background[] = [
  { id: "paper", color: "#fbfaf7", text: "#26231f", dark: false },
  { id: "white", color: "#ffffff", text: "#151515", dark: false },
  { id: "cream", color: "#f5eedf", text: "#2e2820", dark: false },
  { id: "sepia", color: "#ebdcc0", text: "#3a2e20", dark: false },
  { id: "sage", color: "#e1e8dc", text: "#1f2a20", dark: false },
  { id: "slate", color: "#2a2d33", text: "#d6d7d9", dark: true },
  { id: "night", color: "#18181a", text: "#cfccc6", dark: true },
  { id: "black", color: "#000000", text: "#b3b1ad", dark: true },
];

export interface FontOption {
  id: string;
  label: string;
  family: string;
}

export const FONTS: FontOption[] = [
  { id: "literata", label: "Literata", family: '"Literata Variable", Georgia, serif' },
  { id: "source-serif", label: "Source Serif", family: '"Source Serif 4 Variable", Georgia, serif' },
  { id: "lora", label: "Lora", family: '"Lora Variable", Georgia, serif' },
  { id: "merriweather", label: "Merriweather", family: '"Merriweather Variable", Georgia, serif' },
  { id: "garamond", label: "EB Garamond", family: '"EB Garamond Variable", Garamond, serif' },
  { id: "georgia", label: "Georgia", family: "Georgia, serif" },
  { id: "inter", label: "Inter", family: '"Inter Variable", system-ui, sans-serif' },
  { id: "atkinson", label: "Atkinson", family: '"Atkinson Hyperlegible", system-ui, sans-serif' },
  { id: "system", label: "System", family: "system-ui, -apple-system, sans-serif" },
];

export function fontFamily(id: string) {
  return (FONTS.find((f) => f.id === id) ?? FONTS[0]).family;
}

export function resolveDark(mode: ThemeMode) {
  return mode === "dark" || (mode === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
}

export function resolveBackground(settings: ReaderSettings, dark: boolean): Background {
  const picked = BACKGROUNDS.find((b) => b.id === settings.background);
  return picked ?? BACKGROUNDS.find((b) => b.id === (dark ? "night" : "paper"))!;
}

export function parseSettings<T>(data: string | undefined, defaults: T): Partial<T> {
  if (!data) return {};
  try {
    const parsed = JSON.parse(data);
    return Object.fromEntries(Object.entries(parsed).filter(([k]) => k in (defaults as object))) as Partial<T>;
  } catch {
    return {};
  }
}

/** Settings that change the text layout, used to cache page counts. */
export function layoutKey(s: ReaderSettings, width: number, height: number) {
  return [s.font, s.fontSize, s.lineHeight, s.weight, s.tracking, s.paragraphSpacing, s.margin, s.align, s.hyphenate, s.pages, width, height].join("|");
}
