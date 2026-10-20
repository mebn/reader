/**
 * Character-offset ranges inside a root element. Offsets are stable across layouts,
 * which makes them a good way to store highlights.
 */

export const HIGHLIGHT_COLORS: Record<string, string> = {
  yellow: "#f5c84c",
  green: "#7fcf8a",
  blue: "#6fb3f0",
  pink: "#f08fb8",
};

function textNodes(root: Node): Text[] {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes: Text[] = [];
  while (walker.nextNode()) nodes.push(walker.currentNode as Text);
  return nodes;
}

export function rangeToOffsets(root: Node, range: Range): { start: number; end: number } | null {
  if (!root.contains(range.startContainer) || !root.contains(range.endContainer)) return null;
  const before = document.createRange();
  before.selectNodeContents(root);
  before.setEnd(range.startContainer, range.startOffset);
  const start = before.toString().length;
  return { start, end: start + range.toString().length };
}

export function offsetsToRange(root: Node, start: number, end: number): Range | null {
  const range = document.createRange();
  let pos = 0;
  let started = false;
  for (const node of textNodes(root)) {
    const len = node.data.length;
    if (!started && start <= pos + len) {
      range.setStart(node, Math.max(0, start - pos));
      started = true;
    }
    if (started && end <= pos + len) {
      range.setEnd(node, Math.max(0, end - pos));
      return range;
    }
    pos += len;
  }
  return null;
}

/** Wraps [start, end) in <mark> elements, splitting text nodes as needed. */
export function wrapOffsets(root: Node, start: number, end: number, attrs: Record<string, string>) {
  const segments: Text[] = [];
  let pos = 0;
  for (let node of textNodes(root)) {
    const len = node.data.length;
    const from = Math.max(start, pos);
    const to = Math.min(end, pos + len);
    if (from < to) {
      if (from > pos) node = node.splitText(from - pos);
      if (to < pos + len) node.splitText(to - from);
      segments.push(node);
    }
    pos += len;
    if (pos >= end) break;
  }

  for (const node of segments) {
    if (!node.data.trim()) continue;
    const mark = document.createElement("mark");
    for (const [k, v] of Object.entries(attrs)) mark.setAttribute(k, v);
    node.replaceWith(mark);
    mark.appendChild(node);
  }
}

export function unwrapMarks(root: Element) {
  const marks = root.querySelectorAll("mark[data-annotation]");
  if (!marks.length) return;
  marks.forEach((mark) => mark.replaceWith(...Array.from(mark.childNodes)));
  root.normalize();
}

export function highlightAttrs(id: string, color: string, note: string): Record<string, string> {
  const attrs: Record<string, string> = {
    "data-annotation": id,
    style: `--mark: ${HIGHLIGHT_COLORS[color] ?? HIGHLIGHT_COLORS.yellow}`,
  };
  if (note) attrs["data-note"] = "";
  return attrs;
}
