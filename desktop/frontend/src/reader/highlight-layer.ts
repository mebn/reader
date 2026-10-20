import { HIGHLIGHT_COLORS, offsetsToRange } from "./text-ranges";

export interface HighlightSpan {
  id: string;
  start: number;
  end: number;
  color: string;
  note: boolean;
}

interface Box {
  id: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

/**
 * Paints highlights as shapes behind the text instead of wrapping the text in elements,
 * so adding one never changes hyphenation, kerning or justification and nothing moves.
 *
 * The layer sits at the same origin as the text root and must carry the same transform;
 * boxes are stored relative to the root, so they stay right while it pages.
 */
export class HighlightLayer {
  readonly el = document.createElement("div");
  private boxes: Box[] = [];

  constructor() {
    Object.assign(this.el.style, { position: "absolute", left: "0", top: "0", width: "0", height: "0", pointerEvents: "none" });
  }

  paint(root: HTMLElement, spans: HighlightSpan[]) {
    this.el.replaceChildren();
    this.boxes = [];
    const origin = root.getBoundingClientRect();

    for (const span of spans) {
      const range = offsetsToRange(root, span.start, span.end);
      if (!range) continue;
      const color = HIGHLIGHT_COLORS[span.color] ?? HIGHLIGHT_COLORS.yellow;
      const rects = textRects(range);
      for (const r of rects) {
        const box = { id: span.id, left: r.left - origin.left, top: r.top - origin.top, width: r.width, height: r.height };
        this.boxes.push(box);
        this.el.appendChild(shape(box, `color-mix(in oklab, ${color} 45%, transparent)`, "2px"));
      }
      const last = rects.at(-1);
      if (span.note && last) {
        // A small dot at the end, like a footnote mark, without taking any space in the text.
        const dot = { id: span.id, left: last.right - origin.left - 1, top: last.top - origin.top - 2, width: 5, height: 5 };
        this.el.appendChild(shape(dot, color, "999px"));
      }
    }
  }

  /** The highlight under a point on screen, with the bounds of the line box hit. */
  hit(root: HTMLElement, x: number, y: number): { id: string; rect: DOMRect } | null {
    const origin = root.getBoundingClientRect();
    const px = x - origin.left;
    const py = y - origin.top;
    const box = this.boxes.findLast((b) => px >= b.left && px <= b.left + b.width && py >= b.top && py <= b.top + b.height);
    return box ? { id: box.id, rect: new DOMRect(box.left + origin.left, box.top + origin.top, box.width, box.height) } : null;
  }
}

function shape(box: Box, background: string, radius: string) {
  const el = document.createElement("div");
  Object.assign(el.style, {
    position: "absolute",
    left: `${box.left}px`,
    top: `${box.top}px`,
    width: `${box.width}px`,
    height: `${box.height}px`,
    background,
    borderRadius: radius,
  });
  return el;
}

/**
 * Line boxes of the text inside a range. Measured per text node, because a range's own
 * client rects also include whole boxes of elements it spans, such as entire paragraphs.
 */
function textRects(range: Range): DOMRect[] {
  const rects: DOMRect[] = [];
  const walker = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT);
  let node: Node | null = range.commonAncestorContainer.nodeType === Node.TEXT_NODE ? range.commonAncestorContainer : walker.nextNode();
  for (; node; node = walker.nextNode()) {
    if (!range.intersectsNode(node)) continue;
    const text = node as Text;
    const part = document.createRange();
    part.setStart(text, node === range.startContainer ? range.startOffset : 0);
    part.setEnd(text, node === range.endContainer ? range.endOffset : text.length);
    for (const r of part.getClientRects()) if (r.width > 0.5 && r.height > 0) rects.push(r);
    if (node === range.endContainer) break;
  }
  return rects;
}
