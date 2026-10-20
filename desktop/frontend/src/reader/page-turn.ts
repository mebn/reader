import type { Renderer } from "./types";

export type TurnDirection = "next" | "prev";

/**
 * Timing per direction. Forward, the page leaves at once and eases out, so the turn
 * answers the key press immediately. Backward, the page swings in and settles gently.
 */
const TIMING: Record<TurnDirection, KeyframeAnimationOptions> = {
  next: { duration: 480, easing: "cubic-bezier(0.2, 0.65, 0.3, 1)", fill: "both" },
  prev: { duration: 600, easing: "cubic-bezier(0.45, 0.05, 0.3, 1)", fill: "both" },
};
const PERSPECTIVE = "6000px";

/** The page hinges on the spine at the left edge and swings toward the reader. */
const TURN: Keyframe[] = [
  { transform: "rotateY(0deg)", boxShadow: "0 0 0 rgba(0,0,0,0)" },
  { transform: "rotateY(-22deg)", boxShadow: "-4px 0 20px rgba(0,0,0,0.08)", offset: 0.35 },
  { transform: "rotateY(-92deg)", boxShadow: "-2px 0 10px rgba(0,0,0,0)" },
];

/** Light falls off across the page as it tilts, darkest at the lifted edge. */
const SHADE: Keyframe[] = [
  { opacity: 0 },
  { opacity: 0.6, offset: 0.4 },
  { opacity: 0.8 },
];
const SHADE_GRADIENT =
  "linear-gradient(to right, rgba(0,0,0,0) 0%, rgba(0,0,0,0.02) 50%, rgba(255,255,255,0.06) 75%, rgba(0,0,0,0.12) 100%)";

const LEFT_HALF = "inset(0 50% 0 0)";
const RIGHT_HALF = "inset(0 0 0 50%)";

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

/** A snapshot of the current page that can turn on its own while reading carries on. */
function leaf(renderer: Renderer) {
  const page = renderer.snapshot();
  Object.assign(page.style, {
    pointerEvents: "none",
    transformOrigin: "0 50%",
    backfaceVisibility: "hidden",
    willChange: "transform",
  });
  const shade = document.createElement("div");
  Object.assign(shade.style, { position: "absolute", inset: "0", background: SHADE_GRADIENT, opacity: "0", pointerEvents: "none" });
  page.appendChild(shade);
  return { page, shade };
}

function animate(page: HTMLElement, shade: HTMLElement, reverse: boolean) {
  const options = TIMING[reverse ? "prev" : "next"];
  const turn = page.animate(reverse ? [...TURN].reverse() : TURN, options);
  shade.animate(reverse ? [...SHADE].reverse() : SHADE, options);
  return turn.finished.catch(() => undefined);
}

/**
 * Moves the renderer a page and plays the turn on snapshots, resolving as soon as the
 * new page is in place so the next turn can start while this one is still in the air.
 *
 * Snapshots stack above the renderer's sheet: forward, the old page swings away to
 * reveal the new one; backward, the new page swings in over a copy of the old one.
 */
export async function turnPage(container: HTMLElement, renderer: Renderer, direction: TurnDirection): Promise<boolean> {
  if (reducedMotion()) return renderer[direction]();

  const { sheet } = renderer;
  container.style.perspective = PERSPECTIVE;
  if (renderer.spread) return turnSpread(container, renderer, direction);

  if (direction === "next") {
    const { page, shade } = leaf(renderer);
    // Below pages already in flight, which were turned earlier and sit higher.
    sheet.after(page);
    const moved = await renderer.next();
    if (!moved) {
      page.remove();
      return false;
    }
    void animate(page, shade, false).then(() => page.remove());
    return true;
  }

  const under = renderer.snapshot();
  under.style.pointerEvents = "none";
  sheet.after(under);
  const moved = await renderer.prev();
  if (!moved) {
    under.remove();
    return false;
  }
  const { page, shade } = leaf(renderer);
  // Above everything, so the newest page lands on top of the stack.
  container.appendChild(page);
  void animate(page, shade, true).then(() => {
    page.remove();
    under.remove();
  });
  return true;
}

/** One half of a spread, as a snapshot clipped to that side. */
function half(renderer: Renderer, clip: string, transform = "") {
  const page = renderer.snapshot();
  Object.assign(page.style, {
    pointerEvents: "none",
    clipPath: clip,
    transformOrigin: "50% 50%",
    backfaceVisibility: "hidden",
    transform,
  });
  return page;
}

/**
 * Turns a two-page spread the way a book does: the outer page lifts and swings over
 * the spine in the middle, showing the next page on its back as it lands on the other
 * side. The page it lands on stays put until it is covered.
 */
async function turnSpread(container: HTMLElement, renderer: Renderer, direction: TurnDirection) {
  const forward = direction === "next";
  // Forward the right page turns leftwards; backward the left page turns rightwards.
  const staying = half(renderer, forward ? LEFT_HALF : RIGHT_HALF);
  const front = half(renderer, forward ? RIGHT_HALF : LEFT_HALF);
  container.append(staying, front);

  const moved = await renderer[direction]();
  if (!moved) {
    staying.remove();
    front.remove();
    return false;
  }

  const angle = forward ? 180 : -180;
  const back = half(renderer, forward ? LEFT_HALF : RIGHT_HALF, `rotateY(${angle}deg)`);
  container.append(back);

  const options = TIMING[direction];
  const lift = front.animate(
    [
      { transform: "rotateY(0deg)", filter: "brightness(1)" },
      { transform: `rotateY(${-angle / 2}deg)`, filter: "brightness(0.9)" },
      { transform: `rotateY(${-angle}deg)`, filter: "brightness(0.9)" },
    ],
    options,
  );
  back.animate(
    [
      { transform: `rotateY(${angle}deg)`, filter: "brightness(0.9)" },
      { transform: `rotateY(${angle / 2}deg)`, filter: "brightness(0.9)" },
      { transform: "rotateY(0deg)", filter: "brightness(1)" },
    ],
    options,
  );
  void lift.finished
    .catch(() => undefined)
    .then(() => {
      staying.remove();
      front.remove();
      back.remove();
    });
  return true;
}
