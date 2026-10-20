import type { Renderer } from "./types";

export type TurnDirection = "next" | "prev";

const DURATION = 460;
const EASING = "cubic-bezier(0.32, 0.72, 0, 1)";
const PERSPECTIVE = "perspective(2400px)";

/** The page swings left around its spine while lifting slightly off the stack. */
const LIFT: Keyframe[] = [
  { transform: `${PERSPECTIVE} translateX(0) rotateY(0deg)`, boxShadow: "0 0 0 rgba(0,0,0,0)" },
  { transform: `${PERSPECTIVE} translateX(-35%) rotateY(14deg)`, boxShadow: "18px 0 40px rgba(0,0,0,0.18)", offset: 0.45 },
  { transform: `${PERSPECTIVE} translateX(-108%) rotateY(4deg)`, boxShadow: "24px 0 50px rgba(0,0,0,0)" },
];

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

/**
 * Turns the page with an animation and resolves to whether the page changed.
 *
 * A snapshot of the current page is layered in before the renderer moves, so no frame
 * ever shows the new page in the wrong place. Forward, the old page swings away to
 * reveal the new one; backward, the new page swings in over the old one.
 */
export async function turnPage(container: HTMLElement, renderer: Renderer, direction: TurnDirection): Promise<boolean> {
  if (reducedMotion()) return renderer[direction]();

  const { sheet } = renderer;
  const snapshot = renderer.snapshot();
  Object.assign(snapshot.style, { pointerEvents: "none", transformOrigin: "0 50%" });

  if (direction === "next") {
    snapshot.style.zIndex = "2";
    container.appendChild(snapshot);
    const moved = await renderer.next();
    if (moved) await snapshot.animate(LIFT, { duration: DURATION, easing: EASING }).finished.catch(() => undefined);
    snapshot.remove();
    return moved;
  }

  snapshot.style.zIndex = "0";
  container.prepend(snapshot);
  Object.assign(sheet.style, { zIndex: "1", transformOrigin: "0 50%", transform: LIFT[2].transform as string });
  const moved = await renderer.prev();
  if (moved) {
    await sheet.animate([...LIFT].reverse(), { duration: DURATION, easing: EASING }).finished.catch(() => undefined);
  }
  Object.assign(sheet.style, { zIndex: "", transform: "" });
  snapshot.remove();
  return moved;
}
