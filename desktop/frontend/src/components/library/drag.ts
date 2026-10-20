import { useEffect, useId, useRef, useState } from "react";
import { moveFolder, updateBook } from "@/lib/actions";
import { useLibrary } from "@/store/library";

/**
 * Moving books and folders between folders with the pointer. This is done by hand
 * rather than with HTML drag and drop, because during a native drag the OS owns the
 * cursor; here it can be a grabbing hand throughout, with the cover following along.
 */

export type DragItem = { kind: "book" | "folder"; id: string };

interface Target {
  onDrop(item: DragItem): void;
  setOver(over: boolean): void;
}

const THRESHOLD = 5;
const targets = new Map<string, Target>();

function targetAt(x: number, y: number) {
  const el = document.elementFromPoint(x, y)?.closest<HTMLElement>("[data-drop-target]");
  return el ? (el.dataset.dropTarget ?? null) : null;
}

/** Swallows the click that follows letting go, so dropping doesn't also open the item. */
function swallowNextClick() {
  const stop = (e: MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
  };
  window.addEventListener("click", stop, { capture: true, once: true });
  setTimeout(() => window.removeEventListener("click", stop, { capture: true }), 0);
}

function ghostOf(source: HTMLElement) {
  const art = source.querySelector<HTMLElement>("[data-drag-image]") ?? source;
  const rect = art.getBoundingClientRect();
  const ghost = art.cloneNode(true) as HTMLElement;
  const width = Math.min(rect.width, 110);
  Object.assign(ghost.style, {
    position: "fixed",
    left: "0",
    top: "0",
    width: `${width}px`,
    margin: "0",
    zIndex: "100",
    pointerEvents: "none",
    opacity: "0.92",
    filter: "drop-shadow(0 12px 24px rgb(0 0 0 / 0.25))",
    transition: "scale 150ms ease-out",
    scale: "0.9",
  });
  return { ghost, width };
}

/** Props that let an element be picked up and dropped on a {@link useDropTarget}. */
export function dragSource(item: DragItem) {
  return {
    onPointerDown(e: React.PointerEvent<HTMLElement>) {
      if (e.button !== 0 || e.ctrlKey || e.pointerType === "touch") return;
      const source = e.currentTarget;
      const start = { x: e.clientX, y: e.clientY };
      let ghost: HTMLElement | null = null;
      let half = 0;
      let over: string | null = null;

      const setOver = (key: string | null) => {
        if (key === over) return;
        if (over) targets.get(over)?.setOver(false);
        over = key;
        if (over) targets.get(over)?.setOver(true);
      };

      const move = (ev: PointerEvent) => {
        if (!ghost) {
          if (Math.hypot(ev.clientX - start.x, ev.clientY - start.y) < THRESHOLD) return;
          const made = ghostOf(source);
          ghost = made.ghost;
          half = made.width / 2;
          document.body.appendChild(ghost);
          requestAnimationFrame(() => ghost && (ghost.style.scale = "1"));
          document.documentElement.classList.add("dragging-item");
          source.style.opacity = "0.35";
        }
        ghost.style.translate = `${ev.clientX - half}px ${ev.clientY - half * 0.6}px`;
        const key = targetAt(ev.clientX, ev.clientY);
        setOver(key && !source.contains(document.querySelector(`[data-drop-target="${key}"]`)) ? key : null);
      };

      const end = (drop: boolean) => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
        window.removeEventListener("pointercancel", cancel);
        window.removeEventListener("keydown", key, true);
        if (!ghost) return;
        const target = over ? targets.get(over) : undefined;
        setOver(null);
        ghost.remove();
        source.style.opacity = "";
        document.documentElement.classList.remove("dragging-item");
        swallowNextClick();
        if (drop) target?.onDrop(item);
      };
      const up = () => end(true);
      const cancel = () => end(false);
      const key = (ev: KeyboardEvent) => {
        if (ev.key !== "Escape" || !ghost) return;
        ev.preventDefault();
        ev.stopPropagation();
        end(false);
      };

      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up);
      window.addEventListener("pointercancel", cancel);
      window.addEventListener("keydown", key, true);
    },
  };
}

/** Makes an element accept dragged books and folders. */
export function useDropTarget(onDrop: (item: DragItem) => void) {
  const key = useId();
  const [over, setOver] = useState(false);
  const latest = useRef(onDrop);
  latest.current = onDrop;

  useEffect(() => {
    targets.set(key, { onDrop: (item) => latest.current(item), setOver });
    return () => void targets.delete(key);
  }, [key]);

  return { over, props: { "data-drop-target": key } };
}

export function moveItem(item: DragItem, folderId: string | null) {
  const { books, folders } = useLibrary.getState();
  if (item.kind === "book" && books[item.id]) updateBook(books[item.id], { folderId });
  if (item.kind === "folder" && folders[item.id] && item.id !== folderId) moveFolder(folders[item.id], folderId);
}
