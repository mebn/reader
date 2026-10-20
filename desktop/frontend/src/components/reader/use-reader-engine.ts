import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { saveProgress } from "@/lib/actions";
import type { Annotation, Book, Locator } from "@/lib/types";
import { platform } from "@/platform";
import { createRenderer, type Appearance, type Position, type Renderer } from "@/reader";
import { openDocument, type TocEntry } from "@/reader/formats";
import { turnPage, type TurnDirection } from "@/reader/page-turn";
import { useLibrary } from "@/store/library";
import { useSession } from "@/store/session";

const SAVE_DELAY = 800;
const RESIZE_DELAY = 120;

type Status = { state: "loading" } | { state: "ready" } | { state: "error"; message: string };

interface EngineOptions {
  book: Book;
  container: React.RefObject<HTMLDivElement | null>;
  appearance: Appearance;
  annotations: Annotation[];
  onAnnotationClick(id: string, rect: DOMRect): void;
}

/** Opens a book into a renderer and wires it to settings, progress and sync. */
export function useReaderEngine({ book, container, appearance, annotations, onAnnotationClick }: EngineOptions) {
  const [status, setStatus] = useState<Status>({ state: "loading" });
  const [position, setPosition] = useState<Position | null>(null);
  const [toc, setToc] = useState<TocEntry[]>([]);
  const renderer = useRef<Renderer | null>(null);
  const turning = useRef(false);
  const lastSaved = useRef<{ locator: string; at: number }>({ locator: "", at: 0 });

  const latest = useRef({ book, appearance, annotations, onAnnotationClick });
  latest.current = { book, appearance, annotations, onAnnotationClick };

  // Open the book once per book id.
  useEffect(() => {
    const el = container.current;
    if (!el) return;
    let cancelled = false;
    let instance: Renderer | null = null;
    let destroyDoc = () => {};
    setStatus({ state: "loading" });

    (async () => {
      const blob = await platform().bookFile(latest.current.book, useSession.getState().session!);
      const doc = await openDocument(blob, latest.current.book.format, latest.current.book.fileName);
      destroyDoc = () => doc.destroy();
      if (cancelled) return destroyDoc();

      instance = createRenderer(el, doc, book.id, {
        onChange: setPosition,
        onAnnotationClick: (id, rect) => latest.current.onAnnotationClick(id, rect),
        onExternalLink: (url) => platform().openUrl(url),
      });
      await instance.setAppearance(latest.current.appearance);
      instance.setAnnotations(latest.current.annotations);

      const saved = useLibrary.getState().progress[book.id];
      lastSaved.current = { locator: saved?.locator ?? "", at: saved?.modifiedAt ?? 0 };
      await instance.goTo(saved ? (JSON.parse(saved.locator) as Locator) : {});
      if (cancelled) return;

      renderer.current = instance;
      setToc(doc.toc);
      setStatus({ state: "ready" });
    })().catch((err) => {
      console.error(err);
      if (!cancelled) setStatus({ state: "error", message: (err as Error).message });
    });

    return () => {
      cancelled = true;
      renderer.current = null;
      instance?.destroy();
      destroyDoc();
    };
  }, [book.id, container]);

  const appearanceKey = JSON.stringify(appearance);
  useEffect(() => {
    void renderer.current?.setAppearance(latest.current.appearance);
  }, [appearanceKey]);

  useEffect(() => {
    renderer.current?.setAnnotations(annotations);
  }, [annotations, status.state]);

  // Re-paginate when the window is resized.
  useEffect(() => {
    const el = container.current;
    if (!el) return;
    let timer = 0;
    const observer = new ResizeObserver(() => {
      clearTimeout(timer);
      timer = window.setTimeout(() => void renderer.current?.resize(), RESIZE_DELAY);
    });
    observer.observe(el);
    return () => {
      observer.disconnect();
      clearTimeout(timer);
    };
  }, [container]);

  // Save the reading position shortly after it settles.
  useEffect(() => {
    if (status.state !== "ready" || !position) return;
    const locator = JSON.stringify(position.locator);
    if (locator === lastSaved.current.locator) return;
    const timer = setTimeout(() => {
      saveProgress(book.id, position.locator, position.percent);
      lastSaved.current = { locator, at: Date.now() };
    }, SAVE_DELAY);
    return () => clearTimeout(timer);
  }, [book.id, position, status.state]);

  // Offer to jump when another device reads further while this one is open.
  useEffect(
    () =>
      useLibrary.subscribe((state, prev) => {
        const remote = state.progress[book.id];
        if (!remote || remote === prev.progress[book.id] || remote.modifiedAt <= lastSaved.current.at + 1000) return;
        if (remote.locator === lastSaved.current.locator || !renderer.current) return;
        const locator = JSON.parse(remote.locator) as Locator;
        if (renderer.current.isVisible(locator)) return;
        lastSaved.current = { locator: remote.locator, at: remote.modifiedAt };
        toast(`Continue at ${Math.round(remote.percent * 100)}%?`, {
          description: "You read further on another device.",
          action: { label: "Go", onClick: () => void renderer.current?.goTo(locator) },
          duration: 10_000,
        });
      }),
    [book.id],
  );

  const turn = useCallback(
    async (direction: TurnDirection) => {
      const el = container.current;
      if (!renderer.current || !el || turning.current) return;
      turning.current = true;
      try {
        getSelection()?.removeAllRanges();
        await turnPage(el, renderer.current, direction);
      } finally {
        turning.current = false;
      }
    },
    [container],
  );

  const goTo = useCallback(async (target: Locator | TocEntry) => {
    const r = renderer.current;
    if (!r) return;
    const fadeOut = r.sheet.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, fill: "forwards" });
    await fadeOut.finished;
    if ("label" in target) await r.goToToc(target);
    else await r.goTo(target);
    const fadeIn = r.sheet.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220 });
    fadeOut.cancel();
    await fadeIn.finished;
  }, []);

  return { status, position, toc, renderer, turn, goTo };
}
