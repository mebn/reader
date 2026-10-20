import type { Annotation, Locator } from "@/lib/types";
import { fontFamily, layoutKey } from "@/lib/settings";
import type { ReflowDocument, TocEntry } from "../formats";
import { cloneWithCanvases } from "../page-turn";
import { highlightAttrs, offsetsToRange, rangeToOffsets, unwrapMarks, wrapOffsets } from "../text-ranges";
import type { Appearance, Position, Renderer, RendererEvents, TextSelection } from "../types";

const MAX_COLUMN = 680;
const PAD_TOP = 52;
const PAD_BOTTOM = 52;
const IMAGE_TIMEOUT = 1500;

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

  private appearance!: Appearance;
  private geometry: Geometry = { column: 0, gap: 0, height: 0, span: 1 };
  private chapter = 0;
  private page = 0;
  private chapterPages = 1;
  private bookPages: number[] | null = null;
  private paginateToken = 0;
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

    this.viewport.appendChild(this.content);
    this.sheet.appendChild(this.viewport);
    container.append(this.sheet, this.measurer);
    this.content.addEventListener("click", this.onClick);
  }

  get position(): Position {
    const fraction = this.page / this.chapterPages;
    const locator: Locator = { chapter: this.chapter, fraction };
    const total = this.bookPages?.reduce((a, b) => a + b, 0) ?? null;
    const before = this.bookPages?.slice(0, this.chapter).reduce((a, b) => a + b, 0) ?? 0;
    const page = this.bookPages ? before + this.page + 1 : null;
    return {
      chapter: this.chapter,
      chapterCount: this.doc.chapterCount,
      page,
      pageCount: total,
      percent: total && page ? Math.min(1, (page + this.geometry.span - 1) / total) : (this.chapter + fraction) / this.doc.chapterCount,
      locator,
    };
  }

  async setAppearance(appearance: Appearance) {
    this.appearance = appearance;
    this.sheet.style.background = appearance.background;
    await this.relayout();
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

  isVisible(locator: Locator) {
    if (locator.chapter !== this.chapter) return false;
    const page = locator.start !== undefined ? this.pageOfOffset(locator.start) : Math.floor((locator.fraction ?? 0) * this.chapterPages + 1e-6);
    return page >= this.page && page < this.page + this.geometry.span;
  }

  destroy() {
    this.paginateToken++;
    this.content.removeEventListener("click", this.onClick);
    this.sheet.remove();
    this.measurer.remove();
  }

  // Layout

  private async relayout() {
    const fraction = this.chapterPages ? this.page / this.chapterPages : 0;
    this.geometry = this.computeGeometry();
    this.applyStyles(this.content);
    this.applyStyles(this.measurer);

    if (this.content.childNodes.length) {
      this.chapterPages = this.countPages(this.content);
      this.page = this.alignPage(Math.floor(fraction * this.chapterPages + 1e-6));
      this.applyTransform();
    }
    this.bookPages = pageCountCache.get(this.cacheKey()) ?? null;
    this.emit();
    if (!this.bookPages) void this.paginate();
  }

  private computeGeometry(): Geometry {
    const { settings } = this.appearance;
    const width = this.container.clientWidth;
    const height = Math.max(120, this.container.clientHeight - PAD_TOP - PAD_BOTTOM);
    const margin = Math.min(settings.margin, width / 8);
    const span: 1 | 2 = settings.pages === 2 && width > 760 ? 2 : 1;
    const gap = margin * 2;
    const available = width - margin * 2;
    const column = span === 2 ? Math.floor((available - gap) / 2) : Math.min(MAX_COLUMN, Math.floor(available));

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
    this.content.style.transform = `translate3d(${-this.page * stride}px, 0, 0)`;
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
    const range = offsetsToRange(this.content, offset, offset + 1);
    const rect = range?.getClientRects()[0];
    if (!rect) return this.page;
    const left = rect.left - this.content.getBoundingClientRect().left;
    return this.alignPage(Math.floor(left / (this.geometry.column + this.geometry.gap)));
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

  private async renderChapter(index: number) {
    const fragment = await this.doc.loadChapter(index);
    this.chapter = index;
    this.content.style.transform = "";
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
      const fragment = await this.doc.loadChapter(i);
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
    unwrapMarks(this.content);
    for (const a of this.annotations) {
      if (a.kind !== "highlight") continue;
      const loc = JSON.parse(a.locator) as Locator;
      if (loc.chapter !== this.chapter || loc.start === undefined || loc.end === undefined) continue;
      wrapOffsets(this.content, loc.start, loc.end, highlightAttrs(a.id, a.color, a.note));
    }
  }

  private emit() {
    this.events.onChange(this.position);
  }

  private onClick = (e: MouseEvent) => {
    const target = e.target as HTMLElement;
    const mark = target.closest("mark[data-annotation]");
    if (mark && getSelection()?.isCollapsed) {
      e.stopPropagation();
      this.events.onAnnotationClick(mark.getAttribute("data-annotation")!, mark.getBoundingClientRect());
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
