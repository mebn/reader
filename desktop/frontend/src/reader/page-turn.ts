import type { PageTurn } from "@/lib/settings";
import type { Renderer } from "./types";

export type TurnDirection = "next" | "prev";

const FADE_DURATION = 200;
const SLIDE_DURATION = 250;
const EASE_OUT = "cubic-bezier(0.2, 0.8, 0.2, 1)";

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

/** Ends the turn still playing, if any, so a new one never lags behind it. */
let finishPlaying = () => {};

/**
 * Moves the renderer a page, then plays the turn on the sheet and a snapshot of the old
 * page laid over it. Resolves once the new page is in place, not when the animation ends,
 * so the next turn can start straight away and cut this one short.
 */
export async function turnPage(renderer: Renderer, direction: TurnDirection, style: PageTurn): Promise<boolean> {
  finishPlaying();
  // Sliding is a lot of motion; with less asked for, the page only fades.
  const effect = style === "slide" && reducedMotion() ? "fade" : style;
  if (effect === "instant") return renderer[direction]();

  const old = renderer.snapshot();
  old.style.pointerEvents = "none";
  renderer.sheet.after(old);
  const moved = await renderer[direction]();
  if (!moved) {
    old.remove();
    return false;
  }

  let animations: Animation[];
  if (effect === "fade") {
    animations = [old.animate([{ opacity: 1 }, { opacity: 0 }], { duration: FADE_DURATION, easing: "ease-out", fill: "forwards" })];
  } else {
    // Forward the new page comes in from the right and pushes the old one off to the left.
    const away = direction === "next" ? "-100%" : "100%";
    const from = direction === "next" ? "100%" : "-100%";
    const timing = { duration: SLIDE_DURATION, easing: EASE_OUT };
    animations = [
      old.animate([{ transform: "translateX(0)" }, { transform: `translateX(${away})` }], { ...timing, fill: "forwards" }),
      renderer.sheet.animate([{ transform: `translateX(${from})` }, { transform: "translateX(0)" }], timing),
    ];
  }
  const finish = () => {
    if (finishPlaying === finish) finishPlaying = () => {};
    animations.forEach((a) => a.finish());
    old.remove();
  };
  finishPlaying = finish;
  animations[0].onfinish = finish;
  return true;
}
