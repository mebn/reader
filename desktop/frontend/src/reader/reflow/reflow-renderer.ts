import type { Annotation, Locator } from "@/lib/types";
import { fontFamily, layoutKey } from "@/lib/settings";
import { scopeBookCss } from "../book-styles";
import type { ReflowDocument, TocEntry } from "../formats";
import { stripPresentation } from "../formats/dom";
import { cloneWithCanvases } from "../page-turn";
import { HighlightLayer } from "../highlight-layer";
import { offsetsToRange, rangeToOffsets } from "../text-ranges";
import type { Appearance, Position, Renderer, RendererEvents, TextSelection } from "../types";

const PAD_TOP = 52;
const PAD_BOTTOM = 52;
const IMAGE_TIMEOUT = 1500;
/** Numbering the whole book's pages waits until the layout has settled, such as after a resize. */
const PAGINATE_DELAY = 300;

/** Page counts per layout, shared across books opened in this window. */
const pageCountCache = new Map<string, number[]>();

interface Geometry {
  column: number;
  gap: number;
  height: number;
  /** Columns visible at once. */
  span: 1 | 2;
}

/**
 * Lays chapters out with CSS multi-column and pages by translating the column strip.
 * Each chapter is measured in an invisible twin so the whole book has page numbers.
 */
export class ReflowRenderer implements Renderer {
  readonly sheet = document.createElement("div");
  private viewport = document.createElement("div");
  private content = document.createElement("div");
  private measurer = document.createElement("div");
  private highlights = new HighlightLayer();
  /** The book's own CSS, for original styles. */
  private bookStyle = document.createElement("style");
  private bookCss = new Set<string>();

  private appearance!: Appearance;
  private geometry: Geometry = { column: 0, gap: 0, height: 0, span: 1 };
  private chapter = 0;
  private page = 0;
  private chapterPages = 1;
  private bookPages: number[] | null = null;
  private paginateToken = 0;
  private paginateTimer = 0;
  private annotations: Annotation[] = [];

  constructor(
    private container: HTMLElement,
    private doc: ReflowDocument,
    private bookId: string,
    private events: RendererEvents,
  ) {
    Object.assign(this.sheet.style, { position: "absolute", inset: "0", overflow: "hidden" });
    Object.assign(this.viewport.style, { position: "absolute", overflow: "hidden" });
    this.content.className = this.measurer.className = "book-content";
    this.content.lang = this.measurer.lang = doc.metadata.language || "en";
    Object.assign(this.measurer.style, { position: "fixed", left: "-100000px", top: "0", visibility: "hidden", pointerEvents: "none" });

    // Highlights paint behind the text: the layer comes first and the text is positioned,
    // so it stacks above.
    this.content.style.position = "relative";
    this.viewport.append(this.highlights.el, this.content);
    this.sheet.append(this.bookStyle, this.viewport);
    container.append(this.sheet, this.measurer);
    this.content.addEventListener("click", this.onClick);
    this.content.addEventListener("pointermove", this.onPointerMove);
    document.fonts.addEventListener("loadingdone", this.onFontsLoaded);
  }

  get position(): Position {
    const fraction = this.page / this.chapterPages;
    // The first character on the page pins the position exactly, whatever the window size
    // or device; the fraction is for readers that don't know it.
    const start = this.firstOffsetOnPage();
    const locator: Locator = start === null ? { chapter: this.chapter, fraction } : { chapter: this.chapter, fraction, start };
    const total = this.bookPages?.reduce((a, b) => a + b, 0) ?? null;
    const before = this.bookPages?.slice(0, this.chapter).reduce((a, b) => a + b, 0) ?? 0;
    const page = this.bookPages ? before + this.page + 1 : null;
    return {
      chapter: this.chapter,
      chapterCount: this.doc.chapterCount,
      page,
      pageCount: total,
      chapterPage: this.page + 1,
      chapterPageCount: this.chapterPages,
      percent: total && page ? Math.min(1, (page + this.geometry.span - 1) / total) : (this.chapter + fraction) / this.doc.chapterCount,
      locator,
    };
  }

  get spread() {
    return this.geometry.span === 2;
  }

  async setAppearance(appearance: Appearance) {
    const restyle = this.appearance && appearance.settings.originalStyles !== this.appearance.settings.originalStyles;
    this.appearance = appearance;
    this.sheet.style.background = appearance.background;
    this.content.toggleAttribute("data-original", appearance.settings.originalStyles);
    this.measurer.toggleAttribute("data-original", appearance.settings.originalStyles);
    await this.relayout(restyle);
  }

  async resize() {
    await this.relayout();
  }

  async goTo(locator: Locator) {
    const chapter = clamp(locator.chapter ?? 0, 0, this.doc.chapterCount - 1);
    if (chapter !== this.chapter || !this.content.childNodes.length) await this.renderChapter(chapter);
    if (locator.start !== undefined) this.page = this.pageOfOffset(locator.start);
    else this.page = this.alignPage(Math.floor((locator.fraction ?? 0) * this.chapterPages + 1e-6));
    this.applyTransform();
    this.emit();
  }

  async goToToc(entry: TocEntry) {
    if (entry.chapter === undefined) return;
    await this.goToAnchor(entry.chapter, entry.anchor);
  }

  async next() {
    const step = this.geometry.span;
    if (this.page + step < this.chapterPages) {
      this.page += step;
    } else if (this.chapter < this.doc.chapterCount - 1) {
      await this.renderChapter(this.chapter + 1);
      this.page = 0;
    } else {
      return false;
    }
    this.applyTransform();
    this.emit();
    return true;
  }

  async prev() {
    const step = this.geometry.span;
    if (this.page > 0) {
      this.page = Math.max(0, this.page - step);
    } else if (this.chapter > 0) {
      await this.renderChapter(this.chapter - 1);
      this.page = this.alignPage(this.chapterPages - 1);
    } else {
      return false;
    }
    this.applyTransform();
    this.emit();
    return true;
  }

  snapshot() {
    return cloneWithCanvases(this.sheet);
  }

  setAnnotations(annotations: Annotation[]) {
    this.annotations = annotations;
    this.paintHighlights();
  }

  selection(): TextSelection | null {
    const sel = getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
    const range = sel.getRangeAt(0);
    const offsets = rangeToOffsets(this.content, range);
    const text = sel.toString().replace(/\s+/g, " ").trim();
    if (!offsets || !text) return null;
    return { locator: { chapter: this.chapter, ...offsets }, text, rect: range.getBoundingClientRect() };
  }

  textOf(locator: Locator) {
    if (locator.chapter !== this.chapter || locator.start === undefined || locator.end === undefined) return null;
    const range = offsetsToRange(this.content, locator.start, locator.end);
    return range ? range.toString().replace(/\s+/g, " ").trim() : null;
  }

  pageOf(locator: Locator) {
    if (!this.bookPages) return null;
    const chapter = clamp(locator.chapter ?? 0, 0, this.bookPages.length - 1);
    const before = this.bookPages.slice(0, chapter).reduce((a, b) => a + b, 0);
    const inChapter =
      chapter === this.chapter && locator.start !== undefined
        ? this.pageOfOffset(locator.start)
        : Math.floor((locator.fraction ?? 0) * this.bookPages[chapter] + 1e-6);
    return before + clamp(inChapter, 0, this.bookPages[chapter] - 1) + 1;
  }

  isVisible(locator: Locator) {
    if (locator.chapter !== this.chapter) return false;
    const page = locator.start !== undefined ? this.pageOfOffset(locator.start) : Math.floor((locator.fraction ?? 0) * this.chapterPages + 1e-6);
    return page >= this.page && page < this.page + this.geometry.span;
  }

  destroy() {
    this.paginateToken++;
    clearTimeout(this.paginateTimer);
    this.content.removeEventListener("click", this.onClick);
    this.content.removeEventListener("pointermove", this.onPointerMove);
    document.fonts.removeEventListener("loadingdone", this.onFontsLoaded);
    this.sheet.remove();
    this.measurer.remove();
  }

  // Layout

  /** Lays the chapter out again; `reload` when its content changes too, not just its size. */
  private async relayout(reload = false) {
    const fraction = this.chapterPages ? this.page / this.chapterPages : 0;
    // Keeps the same text at the top of the page, not the same share of the chapter.
    const start = this.content.childNodes.length ? this.firstOffsetOnPage() : null;
    this.geometry = this.computeGeometry();
    this.applyStyles(this.content);
    this.applyStyles(this.measurer);

    if (reload && this.content.childNodes.length) await this.renderChapter(this.chapter);
    if (this.content.childNodes.length) {
      this.chapterPages = this.countPages(this.content);
      this.page = start !== null ? this.pageOfOffset(start) : this.alignPage(Math.floor(fraction * this.chapterPages + 1e-6));
      this.applyTransform();
      this.paintHighlights();
    }
    this.bookPages = pageCountCache.get(this.cacheKey()) ?? null;
    this.emit();
    // Stop any count for an older layout now; start a fresh one once resizing settles.
    this.paginateToken++;
    clearTimeout(this.paginateTimer);
    if (!this.bookPages) this.paginateTimer = window.setTimeout(() => void this.paginate(), PAGINATE_DELAY);
  }

  private computeGeometry(): Geometry {
    const { settings } = this.appearance;
    const width = this.container.clientWidth;
    const height = Math.max(120, this.container.clientHeight - PAD_TOP - PAD_BOTTOM);
    const margin = Math.round((width * settings.sideMargin) / 100);
    const span: 1 | 2 = settings.pages === 2 && width > 760 ? 2 : 1;
    const available = width - margin * 2;
    // Facing pages keep a gap of their own, even with no margins. With one page the gap
    // only spaces the hidden neighbouring pages in the strip.
    const gap = span === 2 ? Math.round(Math.min(96, Math.max(40, width * 0.05))) : Math.max(margin * 2, 40);
    const column = Math.floor(span === 2 ? (available - gap) / 2 : available);

    const visible = span === 2 ? column * 2 + gap : column;
    Object.assign(this.viewport.style, {
      top: `${PAD_TOP}px`,
      height: `${height}px`,
      width: `${visible}px`,
      left: `${Math.round((width - visible) / 2)}px`,
    });
    return { column, gap, height, span };
  }

  private applyStyles(el: HTMLElement) {
    const { settings, text } = this.appearance;
    const { column, gap, height, span } = this.geometry;
    const vars: Record<string, string> = {
      "--reader-font": fontFamily(settings.font),
      "--reader-size": `${settings.fontSize}px`,
      "--reader-leading": String(settings.lineHeight),
      "--reader-align": settings.align,
      "--reader-hyphens": settings.hyphenate ? "auto" : "manual",
      "--reader-text": text,
      "--reader-weight": String(settings.weight),
      "--reader-tracking": `${settings.tracking}em`,
      "--reader-paragraph": `${settings.paragraphSpacing}em`,
      "--reader-page-height": `${height}px`,
    };
    for (const [k, v] of Object.entries(vars)) el.style.setProperty(k, v);
    Object.assign(el.style, {
      height: `${height}px`,
      width: `${span === 2 ? column * 2 + gap : column}px`,
      columnWidth: `${column}px`,
      columnGap: `${gap}px`,
      columnFill: "auto",
    });
  }

  private applyTransform() {
    const stride = this.geometry.column + this.geometry.gap;
    this.content.style.transform = this.highlights.el.style.transform = `translate3d(${-this.page * stride}px, 0, 0)`;
  }

  private countPages(el: HTMLElement) {
    const stride = this.geometry.column + this.geometry.gap;
    return Math.max(1, Math.round((el.scrollWidth + this.geometry.gap) / stride));
  }

  private alignPage(page: number) {
    const clamped = clamp(page, 0, this.chapterPages - 1);
    return clamped - (clamped % this.geometry.span);
  }

  private pageOfOffset(offset: number) {
    const column = this.columnAt(offset, this.content.textContent?.length ?? 0);
    return this.alignPage(Number.isFinite(column) ? column : this.page);
  }

  /** The column of a character; one that takes no space (collapsed whitespace) borrows the next one's. */
  private columnAt(offset: number, length: number) {
    for (let o = offset; o < Math.min(length, offset + 64); o++) {
      const c = this.columnOfOffset(o);
      if (c !== null) return c;
    }
    return Infinity;
  }

  /** The column a character is laid out in, or null for one that takes no space. */
  private columnOfOffset(offset: number): number | null {
    const range = offsetsToRange(this.content, offset, offset + 1);
    const rect = range?.getClientRects()[0];
    if (!rect) return null;
    const left = rect.left - this.content.getBoundingClientRect().left;
    return Math.floor(left / (this.geometry.column + this.geometry.gap));
  }

  /** The offset of the first character shown on the current page, found by bisection. */
  private firstOffsetOnPage(): number | null {
    const length = this.content.textContent?.length ?? 0;
    if (!length) return null;
    let lo = 0;
    let hi = length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.columnAt(mid, length) < this.page) lo = mid + 1;
      else hi = mid;
    }
    return lo < length ? lo : null;
  }

  private async goToAnchor(chapter: number, anchor?: string) {
    if (chapter !== this.chapter || !this.content.childNodes.length) await this.renderChapter(chapter);
    this.page = 0;
    if (anchor) {
      const target = this.content.querySelector(`[id="${CSS.escape(anchor)}"]`);
      if (target) {
        const left = target.getBoundingClientRect().left - this.content.getBoundingClientRect().left;
        this.page = this.alignPage(Math.floor(left / (this.geometry.column + this.geometry.gap)));
      }
    }
    this.applyTransform();
    this.emit();
  }

  /** A chapter as the current settings show it: in the book's own styles, or the reader's. */
  private async loadChapter(index: number) {
    const fragment = await this.doc.loadChapter(index);
    if (!this.appearance.settings.originalStyles) stripPresentation(fragment);
    else if (this.doc.chapterStyles) this.addBookStyles(await this.doc.chapterStyles(index));
    return fragment;
  }

  /** The book's CSS, scoped to its text, collected from every chapter shown or measured. */
  private addBookStyles(css: string) {
    if (!css || this.bookCss.has(css)) return;
    this.bookCss.add(css);
    this.bookStyle.textContent += scopeBookCss(css) + "\n";
  }

  private async renderChapter(index: number) {
    const fragment = await this.loadChapter(index);
    this.chapter = index;
    this.content.style.transform = this.highlights.el.style.transform = "";
    this.content.replaceChildren(fragment);
    await waitForImages(this.content);
    this.paintHighlights();
    this.chapterPages = this.countPages(this.content);
  }

  /** Measures every chapter in the background to number pages across the book. */
  private async paginate() {
    const token = ++this.paginateToken;
    const key = this.cacheKey();
    const counts: number[] = [];
    for (let i = 0; i < this.doc.chapterCount; i++) {
      const fragment = await this.loadChapter(i);
      if (token !== this.paginateToken) return;
      this.measurer.replaceChildren(fragment);
      await waitForImages(this.measurer);
      if (token !== this.paginateToken) return;
      counts.push(this.countPages(this.measurer));
      await new Promise((r) => setTimeout(r, 0));
    }
    this.measurer.replaceChildren();
    pageCountCache.set(key, counts);
    this.bookPages = counts;
    this.emit();
  }

  private cacheKey() {
    return `${this.bookId}|${layoutKey(this.appearance.settings, this.geometry.column, this.geometry.height)}|${this.geometry.span}`;
  }

  private paintHighlights() {
    const spans = [];
    // Newest first, so where highlights overlap the latest one's color shows.
    for (const a of [...this.annotations].sort((x, y) => y.modifiedAt - x.modifiedAt)) {
      if (a.kind !== "highlight") continue;
      const loc = JSON.parse(a.locator) as Locator;
      if (loc.chapter !== this.chapter || loc.start === undefined || loc.end === undefined) continue;
      spans.push({ id: a.id, start: loc.start, end: loc.end, color: a.color, note: Boolean(a.note) });
    }
    // Only boxes inside a column: a line can report a box below the column's last line or
    // in the gap beside it, where no text shows.
    const { column, gap, height } = this.geometry;
    const stride = column + gap;
    this.highlights.paint(this.content, spans, (b) => {
      const x = ((b.left % stride) + stride) % stride;
      return b.top >= -1 && b.top + b.height <= height + 1 && x + b.width <= column + 1;
    });
  }

  annotationAt(x: number, y: number) {
    return this.highlights.hit(this.content, x, y);
  }

  // Highlights don't receive pointer events, so show they're clickable by hand.
  private onPointerMove = (e: PointerEvent) => {
    this.content.style.cursor = this.annotationAt(e.clientX, e.clientY) ? "pointer" : "";
  };

  /**
   * Fonts load when text first needs them, such as a book's first italics or a newly
   * picked typeface, and the text reflows when they arrive. Lay out again so pages and
   * highlights match it, and count the book's pages afresh.
   */
  private onFontsLoaded = (e: FontFaceSetLoadEvent) => {
    if (!this.appearance) return;
    const family = fontFamily(this.appearance.settings.font);
    if (!e.fontfaces.some((face) => family.includes(face.family.replace(/"/g, "")))) return;
    pageCountCache.delete(this.cacheKey());
    void this.relayout();
  };

  private emit() {
    this.events.onChange(this.position);
  }

  private onClick = (e: MouseEvent) => {
    if (!this.events.canInteract()) return;
    const target = e.target as HTMLElement;
    const hit = this.annotationAt(e.clientX, e.clientY);
    if (hit && getSelection()?.isCollapsed) {
      e.stopPropagation();
      this.events.onAnnotationClick(hit.id, hit.rect);
      return;
    }
    const link = target.closest("a[data-href], a[data-external]");
    if (!link) return;
    e.stopPropagation();
    const external = link.getAttribute("data-external");
    if (external) {
      this.events.onExternalLink(external);
      return;
    }
    const resolved = this.doc.resolveLink(link.getAttribute("data-href")!);
    if (resolved) void this.goToAnchor(resolved.chapter, resolved.anchor);
  };
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function waitForImages(root: HTMLElement) {
  const images = Array.from(root.querySelectorAll("img"));
  const timeout = new Promise((r) => setTimeout(r, IMAGE_TIMEOUT));
  return Promise.race([Promise.all(images.map((img) => img.decode().catch(() => undefined))), timeout]);
}
