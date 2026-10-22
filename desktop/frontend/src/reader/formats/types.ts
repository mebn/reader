export interface BookMetadata {
  title: string;
  author: string;
  /** BCP 47 language tag, used for hyphenation. */
  language?: string;
}

export interface TocEntry {
  label: string;
  depth: number;
  chapter?: number;
  anchor?: string;
  page?: number;
}

export interface LinkTarget {
  chapter: number;
  anchor?: string;
}

/** Text that flows into pages: EPUB, FB2, TXT. */
export interface ReflowDocument {
  layout: "reflow";
  metadata: BookMetadata;
  toc: TocEntry[];
  chapterCount: number;
  /**
   * Returns a fresh, sanitized copy of a chapter's content. It keeps the book's own classes
   * and inline styles; the renderer strips them unless the book is shown in its original styles.
   */
  loadChapter(index: number): Promise<DocumentFragment>;
  /** The book's own CSS for a chapter, with its fonts and images resolved, if it has any. */
  chapterStyles?(index: number): Promise<string>;
  /** Resolves a `data-href` produced by loadChapter. */
  resolveLink(href: string): LinkTarget | null;
  cover(): Promise<Blob | null>;
  destroy(): void;
}

/** Pre-laid-out pages: PDF, comics. */
export interface FixedDocument {
  layout: "fixed";
  metadata: BookMetadata;
  toc: TocEntry[];
  pageCount: number;
  /** Whether pages carry a selectable text layer. */
  hasText: boolean;
  /** Whether pages should be inverted for dark themes. */
  invertInDark: boolean;
  pageAspect(index: number): Promise<number>;
  /** Renders page `index` into `target`, fitted inside width × height. */
  renderPage(index: number, target: HTMLElement, width: number, height: number): Promise<void>;
  cover(): Promise<Blob | null>;
  destroy(): void;
}

export type BookDocument = ReflowDocument | FixedDocument;
