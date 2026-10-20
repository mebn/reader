import type { Annotation, Locator } from "@/lib/types";
import type { FixedDocument, TocEntry } from "../formats";
import { cloneWithCanvases } from "../page-turn";
import { highlightAttrs, rangeToOffsets, unwrapMarks, wrapOffsets } from "../text-ranges";
import type { Appearance, Position, Renderer, RendererEvents, TextSelection } from "../types";

const PAD_Y = 44;
const PAD_X = 24;
const SPREAD_GAP = 4;

/** Shows one or two pre-laid-out pages (PDF, comics) fitted to the window. */
export class FixedRenderer implements Renderer {
  readonly sheet = document.createElement("div");
  private pagesEl = document.createElement("div");
  private slots: HTMLElement[] = [];

  private appearance!: Appearance;
  private page = 0;
  private span: 1 | 2 = 1;
  private renderToken = 0;
  private annotations: Annotation[] = [];
  private chapters: TocEntry[];

  constructor(
    private container: HTMLElement,
    private doc: FixedDocument,
    private events: RendererEvents,
  ) {
    Object.assign(this.sheet.style, { position: "absolute", inset: "0", overflow: "hidden" });
    Object.assign(this.pagesEl.style, {
      position: "absolute",
      inset: `${PAD_Y}px ${PAD_X}px`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: `${SPREAD_GAP}px`,
    });
    this.sheet.appendChild(this.pagesEl);
    container.appendChild(this.sheet);
    this.pagesEl.addEventListener("click", this.onClick);
    this.chapters = doc.toc.filter((e) => e.depth === 0 && e.page !== undefined);
  }

  get position(): Position {
    const chapter = this.chapters.length ? Math.max(0, this.chapters.findLastIndex((c) => c.page! <= this.page)) : null;
    const lastVisible = Math.min(this.doc.pageCount, this.page + this.span);
    const chapterStart = chapter === null ? 0 : this.chapters[chapter].page!;
    const chapterEnd = chapter === null ? this.doc.pageCount : (this.chapters[chapter + 1]?.page ?? this.doc.pageCount);
    return {
      chapter,
      chapterCount: this.chapters.length,
      page: this.page + 1,
      pageCount: this.doc.pageCount,
      chapterPage: chapter === null ? null : Math.max(1, this.page - chapterStart + 1),
      chapterPageCount: chapter === null ? null : Math.max(1, chapterEnd - chapterStart),
      percent: lastVisible / this.doc.pageCount,
      locator: { page: this.page },
    };
  }

  get spread() {
    return this.span === 2;
  }

  async setAppearance(appearance: Appearance) {
    this.appearance = appearance;
    this.sheet.style.background = appearance.background;
    await this.resize();
  }

  async resize() {
    this.span = this.appearance.settings.pages === 2 && this.container.clientWidth > 760 ? 2 : 1;
    this.page = this.align(this.page);
    await this.render();
  }

  async goTo(locator: Locator) {
    this.page = this.align(locator.page ?? 0);
    await this.render();
  }

  async goToToc(entry: TocEntry) {
    if (entry.page !== undefined) await this.goTo({ page: entry.page });
  }

  async next() {
    if (this.page + this.span >= this.doc.pageCount) return false;
    this.page += this.span;
    await this.render();
    return true;
  }

  async prev() {
    if (this.page === 0) return false;
    this.page = Math.max(0, this.page - this.span);
    await this.render();
    return true;
  }

  snapshot() {
    return cloneWithCanvases(this.sheet);
  }

  setAnnotations(annotations: Annotation[]) {
    this.annotations = annotations;
    this.slots.forEach((slot) => this.paintHighlights(slot));
  }

  selection(): TextSelection | null {
    const sel = getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
    const range = sel.getRangeAt(0);
    const layer = (range.startContainer.parentElement?.closest(".textLayer") ?? null) as HTMLElement | null;
    const slot = layer?.closest<HTMLElement>("[data-page-index]");
    if (!layer || !slot) return null;
    const offsets = rangeToOffsets(layer, range);
    const text = sel.toString().replace(/\s+/g, " ").trim();
    if (!offsets || !text) return null;
    return { locator: { page: Number(slot.dataset.pageIndex), ...offsets }, text, rect: range.getBoundingClientRect() };
  }

  annotationAt(x: number, y: number) {
    // PDF highlights are marks in the invisible text layer, so the page itself never moves.
    const mark = document.elementFromPoint(x, y)?.closest<HTMLElement>("mark[data-annotation]");
    return mark && this.sheet.contains(mark) ? { id: mark.dataset.annotation!, rect: mark.getBoundingClientRect() } : null;
  }

  pageOf(locator: Locator) {
    return (locator.page ?? 0) + 1;
  }

  isVisible(locator: Locator) {
    const page = locator.page ?? -1;
    return page >= this.page && page < this.page + this.span;
  }

  destroy() {
    this.renderToken++;
    this.pagesEl.removeEventListener("click", this.onClick);
    this.sheet.remove();
  }

  private align(page: number) {
    const clamped = Math.min(Math.max(0, page), this.doc.pageCount - 1);
    return this.span === 2 ? clamped - (clamped % 2) : clamped;
  }

  private async render() {
    const token = ++this.renderToken;
    const indices = Array.from({ length: this.span }, (_, i) => this.page + i).filter((i) => i < this.doc.pageCount);
    const width = (this.container.clientWidth - PAD_X * 2 - (indices.length - 1) * SPREAD_GAP) / indices.length;
    const height = this.container.clientHeight - PAD_Y * 2;
    const invert = this.doc.invertInDark && this.appearance.dark;

    const slots = indices.map((index) => {
      const slot = document.createElement("div");
      slot.dataset.pageIndex = String(index);
      slot.style.filter = invert ? "invert(0.9) hue-rotate(180deg)" : "";
      return slot;
    });
    await Promise.all(slots.map((slot, i) => this.doc.renderPage(indices[i], slot, width, height)));
    if (token !== this.renderToken) return;

    this.slots = slots;
    this.pagesEl.replaceChildren(...slots);
    slots.forEach((slot) => this.paintHighlights(slot));
    this.events.onChange(this.position);
  }

  private paintHighlights(slot: HTMLElement) {
    const layer = slot.querySelector<HTMLElement>(".textLayer");
    if (!layer) return;
    unwrapMarks(layer);
    const index = Number(slot.dataset.pageIndex);
    for (const a of this.annotations) {
      if (a.kind !== "highlight") continue;
      const loc = JSON.parse(a.locator) as Locator;
      if (loc.page === index && loc.start !== undefined && loc.end !== undefined) {
        wrapOffsets(layer, loc.start, loc.end, highlightAttrs(a.id, a.color, a.note));
      }
    }
  }

  private onClick = (e: MouseEvent) => {
    if (!this.events.canInteract()) return;
    const mark = (e.target as HTMLElement).closest("mark[data-annotation]");
    if (mark && getSelection()?.isCollapsed) {
      e.stopPropagation();
      this.events.onAnnotationClick(mark.getAttribute("data-annotation")!, mark.getBoundingClientRect());
    }
  };
}
