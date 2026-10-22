export type ThemeMode = "light" | "dark" | "system";

export interface ReaderSettings {
  /** Background ids for the page while the app is light and while it is dark. */
  lightBackground: string;
  darkBackground: string;
  font: string;
  fontSize: number;
  lineHeight: number;
  weight: number;
  tracking: number;
  paragraphSpacing: number;
  /** Space beside the text on each side, as a percentage of the window's width; 0 is none. */
  sideMargin: number;
  align: "left" | "justify";
  hyphenate: boolean;
  /** Shows a book with its own styles (headings, alignment, fonts) instead of the reader's. */
  originalStyles: boolean;
  pages: 1 | 2;
  /** What the header shows: in the toolbar, and above the text once the toolbar hides. */
  headerTitle: boolean;
  headerAuthor: boolean;
  headerChapter: boolean;
  headerClock: boolean;
  /** What the line under the text shows. */
  footerChapter: boolean;
  footerChapterPages: boolean;
  footerBookPages: boolean;
  footerPercent: boolean;
}

export type LibraryTab = "all" | "books" | "highlights" | "notes" | "bookmarks";

export const LIBRARY_TABS: [LibraryTab, string][] = [
  ["all", "All"],
  ["books", "Books"],
  ["highlights", "Highlights"],
  ["notes", "Notes"],
  ["bookmarks", "Bookmarks"],
];

export interface AppSettings {
  /** Light or dark for the whole app, the reader included. */
  theme: ThemeMode;
  openInNewWindow: boolean;
  /** The library tab shown when the app starts. */
  defaultTab: LibraryTab;
}

export const DEFAULT_READER: ReaderSettings = {
  lightBackground: "paper",
  darkBackground: "night",
  font: "literata",
  fontSize: 19,
  lineHeight: 1.6,
  weight: 400,
  tracking: 0,
  paragraphSpacing: 0.6,
  sideMargin: 20,
  align: "justify",
  hyphenate: true,
  originalStyles: false,
  pages: 1,
  headerTitle: true,
  headerAuthor: false,
  headerChapter: false,
  headerClock: false,
  footerChapter: false,
  footerChapterPages: true,
  footerBookPages: true,
  footerPercent: false,
};

export const DEFAULT_APP: AppSettings = { theme: "system", openInNewWindow: false, defaultTab: "all" };

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
  const id = dark ? settings.darkBackground : settings.lightBackground;
  return BACKGROUNDS.find((b) => b.id === id) ?? BACKGROUNDS.find((b) => b.id === (dark ? "night" : "paper"))!;
}

/**
 * Older saved settings: one background for both modes, and a header that showed one
 * thing ("title", "chapter" or "none") rather than a set of switches.
 */
function migrate(parsed: Record<string, unknown>) {
  if (typeof parsed.header === "string" && !("headerTitle" in parsed)) {
    parsed.headerTitle = parsed.header === "title";
    parsed.headerChapter = parsed.header === "chapter";
  }
  const old = BACKGROUNDS.find((b) => b.id === parsed.background);
  if (old && !("lightBackground" in parsed) && !("darkBackground" in parsed)) {
    parsed[old.dark ? "darkBackground" : "lightBackground"] = old.id;
  }
  return parsed;
}

export function parseSettings<T>(data: string | undefined, defaults: T): Partial<T> {
  if (!data) return {};
  try {
    const parsed = migrate(JSON.parse(data));
    return Object.fromEntries(Object.entries(parsed).filter(([k]) => k in (defaults as object))) as Partial<T>;
  } catch {
    return {};
  }
}

/** Settings that change the text layout, used to cache page counts. */
export function layoutKey(s: ReaderSettings, width: number, height: number) {
  return [s.font, s.fontSize, s.lineHeight, s.weight, s.tracking, s.paragraphSpacing, s.sideMargin, s.align, s.hyphenate, s.originalStyles, s.pages, width, height].join("|");
}
