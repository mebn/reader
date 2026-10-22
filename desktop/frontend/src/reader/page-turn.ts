import type { Renderer } from "./types";

export type TurnDirection = "next" | "prev";

/**
 * A page turn is a paper curl: the page lifts from its bottom outer corner and folds over
 * towards the spine, showing its back, while the next page shows from under it. iOS draws
 * the same turn with UIKit's page curl, so keep the two looking alike.
 */
const DURATION: Record<TurnDirection, number> = { next: 560, prev: 620 };
/** How far the lifted corner rises on its way over, as a share of the page height. */
const LIFT = 0.14;
/** How strongly the back of a single page shows the print through the paper. */
const SHOW_THROUGH = 0.12;

/** Clones an element including the pixels of any canvases inside it. */
export function cloneWithCanvases(el: HTMLElement): HTMLElement {
  const clone = el.cloneNode(true) as HTMLElement;
  const source = el.querySelectorAll("canvas");
  clone.querySelectorAll("canvas").forEach((canvas, i) => canvas.getContext("2d")?.drawImage(source[i], 0, 0));
  return clone;
}

function reducedMotion() {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

interface Point {
  x: number;
  y: number;
}

/** The leaf that turns, in the container's pixels; `flip` when it turns left to right. */
interface Leaf {
  left: number;
  width: number;
  height: number;
  flip: boolean;
}

/**
 * The fold at progress t (0–1), in the leaf's own coordinates: spine at x = 0, the corner
 * starting at the bottom right and ending mirrored on the far side of the spine. The fold
 * is the line halfway between where the corner was and where it is now.
 */
function foldAt(leaf: Leaf, t: number) {
  const { width: w, height: h } = leaf;
  const k = Math.min(Math.max(t, 0.002), 1);
  const tip = { x: w - 2 * w * k, y: h - h * LIFT * Math.sin(Math.PI * k) };
  const mid = { x: (w + tip.x) / 2, y: (h + tip.y) / 2 };
  const length = Math.hypot(w - tip.x, h - tip.y);
  return { mid, normal: { x: (w - tip.x) / length, y: (h - tip.y) / length }, length };
}

/** The part of the leaf on one side of the fold: the lifted corner's side, or the rest. */
function side(leaf: Leaf, mid: Point, normal: Point, lifted: boolean): Point[] {
  const { width: w, height: h } = leaf;
  const corners = [
    { x: 0, y: 0 },
    { x: w, y: 0 },
    { x: w, y: h },
    { x: 0, y: h },
  ];
  const distance = (p: Point) => (lifted ? 1 : -1) * ((p.x - mid.x) * normal.x + (p.y - mid.y) * normal.y);
  const out: Point[] = [];
  corners.forEach((a, i) => {
    const b = corners[(i + 1) % 4];
    const da = distance(a);
    const db = distance(b);
    if (da >= 0) out.push(a);
    if (da >= 0 !== db >= 0) {
      const k = da / (da - db);
      out.push({ x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k });
    }
  });
  return out;
}

function toContainer(leaf: Leaf, p: Point): Point {
  return { x: leaf.flip ? leaf.left + leaf.width - p.x : leaf.left + p.x, y: p.y };
}

function polygon(points: Point[]) {
  return points.length >= 3 ? `polygon(${points.map((p) => `${p.x}px ${p.y}px`).join(", ")})` : "polygon(0 0, 0 0, 0 0)";
}

function layer(style: Partial<CSSStyleDeclaration> = {}) {
  const el = document.createElement("div");
  Object.assign(el.style, { position: "absolute", inset: "0", pointerEvents: "none" }, style);
  return el;
}

/** A strip that starts at the fold and runs `width` px along `normal`, for shading. */
function strip(background: string) {
  const el = document.createElement("div");
  Object.assign(el.style, { position: "absolute", left: "0", top: "0", transformOrigin: "0 0", background, pointerEvents: "none" });
  return el;
}

function placeStrip(el: HTMLElement, at: Point, normal: Point, width: number, reach: number) {
  const angle = Math.atan2(normal.y, normal.x);
  Object.assign(el.style, {
    width: `${width}px`,
    height: `${reach * 2}px`,
    transform: `translate(${at.x}px, ${at.y}px) rotate(${angle}rad) translateY(${-reach}px)`,
  });
}

/**
 * Builds a curl over the container. `front` is what the leaf shows before it turns (it is
 * clipped away as the corner lifts) and `back` what its other side shows; both are full
 * snapshots of the sheet. Whatever is under the stage shows where the leaf has lifted.
 */
function curl(place: (stage: HTMLElement) => void, leaf: Leaf, front: HTMLElement, back: HTMLElement) {
  const stage = layer({ overflow: "hidden" });

  front.style.pointerEvents = "none";
  // The shadow the lifted page casts on the page under it.
  const under = layer({ left: `${leaf.left}px`, width: `${leaf.width}px`, right: "auto", overflow: "hidden" });
  const cast = strip("linear-gradient(to right, rgba(0,0,0,0.32), rgba(0,0,0,0.12) 35%, rgba(0,0,0,0))");
  under.appendChild(cast);

  // The lifted part, mirrored over the fold so its back shows, with light along the bend.
  const flapShadow = layer({ filter: "drop-shadow(0 2px 10px rgba(0,0,0,0.28))" });
  const flap = layer({ transformOrigin: "0 0" });
  back.style.pointerEvents = "none";
  const sheen = strip("linear-gradient(to right, rgba(255,255,255,0.28), rgba(255,255,255,0) 30%, rgba(0,0,0,0.06) 70%, rgba(0,0,0,0.14))");
  flap.append(back, sheen);
  flapShadow.appendChild(flap);

  stage.append(front, under, flapShadow);
  place(stage);

  const reach = Math.hypot(leaf.width * 2, leaf.height) + 10;

  const render = (t: number) => {
    const { mid, normal, length } = foldAt(leaf, t);
    const at = toContainer(leaf, mid);
    const n = { x: leaf.flip ? -normal.x : normal.x, y: normal.y };

    front.style.clipPath = polygon(side(leaf, mid, normal, false).map((p) => toContainer(leaf, p)));
    flap.style.clipPath = polygon(side(leaf, mid, normal, true).map((p) => toContainer(leaf, p)));

    // Reflection across the fold: x' = x - 2((x - at)·n)n.
    const dot = at.x * n.x + at.y * n.y;
    flap.style.transform = `matrix(${1 - 2 * n.x * n.x}, ${-2 * n.x * n.y}, ${-2 * n.x * n.y}, ${1 - 2 * n.y * n.y}, ${2 * dot * n.x}, ${2 * dot * n.y})`;

    placeStrip(sheen, at, n, Math.max(40, length / 2), reach);
    placeStrip(cast, { x: at.x - leaf.left, y: at.y }, n, Math.min(90, 24 + leaf.width * 0.12), reach);
    cast.style.opacity = String(Math.sin(Math.PI * Math.min(1, t * 1.1)));
    // Light and shadow fade as the page lies flat again, so the landed page doesn't change
    // brightness when the curl is taken away.
    const flat = String(Math.min(1, (1 - t) * 4));
    sheen.style.opacity = flat;
    flapShadow.style.filter = `drop-shadow(0 2px 10px rgba(0,0,0,${0.28 * Math.min(1, (1 - t) * 4)}))`;
  };

  return { stage, render };
}

/** Eases in and out, for a page lifting off and landing. */
function easeInOut(k: number) {
  return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
}

function play(render: (t: number) => void, from: number, to: number, duration: number) {
  render(from);
  return new Promise<void>((resolve) => {
    const start = performance.now();
    const step = (now: number) => {
      const k = Math.min(1, (now - start) / duration);
      render(from + (to - from) * easeInOut(k));
      if (k < 1) requestAnimationFrame(step);
      else resolve();
    };
    requestAnimationFrame(step);
  });
}

/** The paper color of the sheet, for the back of a page. */
function paper(renderer: Renderer) {
  return getComputedStyle(renderer.sheet).backgroundColor || "#fff";
}

/** A single page's back: its own print, mirrored by the fold and faint through the paper. */
function backOf(page: HTMLElement, color: string) {
  const wrap = layer();
  wrap.append(page, layer({ background: color, opacity: String(1 - SHOW_THROUGH) }));
  return wrap;
}

/** One side of a spread, mirrored over the spine so the fold mirrors it back into place. */
function mirroredHalf(snapshot: HTMLElement) {
  const wrap = layer();
  // Mirrored about the middle, which is where the spine is.
  Object.assign(snapshot.style, { transform: "scaleX(-1)", transformOrigin: "50% 50%" });
  wrap.appendChild(snapshot);
  return wrap;
}

/** A snapshot clipped to one half of a spread. */
function half(snapshot: HTMLElement, left: boolean) {
  snapshot.style.clipPath = left ? "inset(0 50% 0 0)" : "inset(0 0 0 50%)";
  snapshot.style.pointerEvents = "none";
  return snapshot;
}

/**
 * Moves the renderer a page and plays the curl on snapshots, resolving as soon as the new
 * page is in place so the next turn can start while this one is still in the air.
 *
 * Either way the old page curls away over the new one, as the outer page of a spread does.
 */
export async function turnPage(container: HTMLElement, renderer: Renderer, direction: TurnDirection): Promise<boolean> {
  if (reducedMotion()) return renderer[direction]();
  if (renderer.spread) return turnSpread(container, renderer, direction);

  // The page turns the way the outer page of a spread does: forward it lifts from its
  // bottom right corner and folds away to the left, backward from its bottom left corner
  // and away to the right, uncovering the page under it either way.
  const forward = direction === "next";
  const leaf: Leaf = { left: 0, width: container.clientWidth, height: container.clientHeight, flip: !forward };
  const front = renderer.snapshot();
  const back = renderer.snapshot();
  // Below pages already in flight, which were turned earlier and sit higher.
  const { stage, render } = curl((el) => renderer.sheet.after(el), leaf, front, backOf(back, paper(renderer)));
  render(0);
  const moved = await renderer[direction]();
  if (!moved) {
    stage.remove();
    return false;
  }
  void play(render, 0, 1, DURATION[direction]).then(() => stage.remove());
  return true;
}

/**
 * Turns a two-page spread the way a book does: the outer page lifts from its bottom
 * corner and folds over the spine, showing the next page on its back as it lands.
 */
async function turnSpread(container: HTMLElement, renderer: Renderer, direction: TurnDirection) {
  const forward = direction === "next";
  const width = container.clientWidth;
  const height = container.clientHeight;
  const middle = width / 2;
  // Forward the right page turns leftwards; backward the left page turns rightwards.
  const leaf: Leaf = forward ? { left: middle, width: middle, height, flip: false } : { left: 0, width: middle, height, flip: true };

  // The whole old spread covers the move; then only the page that stays is kept.
  const staying = renderer.snapshot();
  staying.style.pointerEvents = "none";
  const front = renderer.snapshot();
  const holder = layer();
  holder.appendChild(staying);
  container.appendChild(holder);

  const moved = await renderer[direction]();
  if (!moved) {
    holder.remove();
    return false;
  }

  half(staying, forward);
  // The back of the turning page is the page it lands as, on the other side of the spine.
  const back = mirroredHalf(half(renderer.snapshot(), forward));
  const { stage, render } = curl((el) => holder.after(el), leaf, front, back);
  render(0);
  void play(render, 0, 1, DURATION[direction]).then(() => {
    stage.remove();
    holder.remove();
  });
  return true;
}
