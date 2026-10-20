import type { Annotation, Locator } from "@/lib/types";
import type { ReaderSettings } from "@/lib/settings";
import type { TocEntry } from "./formats";

export interface Position {
  /** 0-based chapter, or null when the book has no chapters. */
  chapter: number | null;
  chapterCount: number;
  /** 1-based page; null while page numbers are still being computed. */
  page: number | null;
  pageCount: number | null;
  /** 1-based page within the current chapter, or null when the book has no chapters. */
  chapterPage: number | null;
  chapterPageCount: number | null;
  /** 0–1 through the whole book. */
  percent: number;
  locator: Locator;
}

export interface Appearance {
  settings: ReaderSettings;
  dark: boolean;
  background: string;
  text: string;
}

export interface TextSelection {
  locator: Locator;
  text: string;
  rect: DOMRect;
}

export interface RendererEvents {
  onChange(position: Position): void;
  onAnnotationClick(id: string, rect: DOMRect): void;
  onExternalLink(url: string): void;
  /** False while a click should only close something, so highlights and links ignore it. */
  canInteract(): boolean;
}

export interface Renderer {
  /** The page surface; page turns animate a snapshot of it. */
  readonly sheet: HTMLElement;
  readonly position: Position;
  /** Whether two facing pages are shown, split at the middle of the sheet. */
  readonly spread: boolean;

  setAppearance(appearance: Appearance): Promise<void>;
  /** Re-paginates after a size change, keeping the reading position. */
  resize(): Promise<void>;

  goTo(locator: Locator): Promise<void>;
  goToToc(entry: TocEntry): Promise<void>;
  next(): Promise<boolean>;
  prev(): Promise<boolean>;

  /** A static copy of the current page surface. */
  snapshot(): HTMLElement;

  setAnnotations(annotations: Annotation[]): void;
  selection(): TextSelection | null;
  /** The highlight under a point on screen, if any. */
  annotationAt(x: number, y: number): { id: string; rect: DOMRect } | null;
  /** Whether a locator is visible on the current page(s). */
  isVisible(locator: Locator): boolean;
  /** The 1-based book page a locator falls on, or null while pages are still being counted. */
  pageOf(locator: Locator): number | null;

  destroy(): void;
}
