import { useCallback, useEffect, useRef, useState } from "react";
import { saveProgress } from "@/lib/actions";
import type { Annotation, Book, Locator } from "@/lib/types";
import { platform } from "@/platform";
import { createRenderer, type Appearance, type Position, type Renderer } from "@/reader";
import { openDocument, type TocEntry } from "@/reader/formats";
import { turnPage, type TurnDirection } from "@/reader/page-turn";
import { useLibrary } from "@/store/library";
import { useSession } from "@/store/session";
import { useBookTransition } from "@/store/transition";

const SAVE_DELAY = 800;
/** Turns that can wait behind the current one, so a held key doesn't run away. */
const MAX_QUEUED_TURNS = 8;

type Status = { state: "loading" } | { state: "ready" } | { state: "error"; message: string };

/** Where another device read up to, offered while it's ahead of this one. */
export interface ContinueOffer {
  locator: Locator;
  label: string;
}


interface EngineOptions {
  book: Book;
  container: React.RefObject<HTMLDivElement | null>;
  appearance: Appearance;
  annotations: Annotation[];
  onAnnotationClick(id: string, rect: DOMRect): void;
  /** See {@link RendererEvents.canInteract}. */
  canInteract?(): boolean;
}

/** Opens a book into a renderer and wires it to settings, progress and sync. */
export function useReaderEngine({ book, container, appearance, annotations, onAnnotationClick, canInteract }: EngineOptions) {
  const [status, setStatus] = useState<Status>({ state: "loading" });
  const [position, setPosition] = useState<Position | null>(null);
  const [toc, setToc] = useState<TocEntry[]>([]);
  const renderer = useRef<Renderer | null>(null);
  const turns = useRef({ queue: Promise.resolve(), pending: 0 });
  const lastSaved = useRef<{ locator: string; at: number }>({ locator: "", at: 0 });
  // Opened at a highlight or note: only a page turn or a jump makes it the reading position.
  const holdPosition = useRef(false);
  // Where reading was before going to a highlight, note or bookmark, to get back to. Going
  // to another one keeps the first place; page turns, contents and links don't touch it.
  const [returnTo, setReturnTo] = useState<Locator | null>(null);
  const [offer, setOffer] = useState<ContinueOffer | null>(null);

  const latest = useRef({ book, appearance, annotations, onAnnotationClick, canInteract });
  latest.current = { book, appearance, annotations, onAnnotationClick, canInteract };

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
        canInteract: () => latest.current.canInteract?.() ?? true,
      });
      await instance.setAppearance(latest.current.appearance);
      instance.setAnnotations(latest.current.annotations);

      const saved = useLibrary.getState().progress[book.id];
      lastSaved.current = { locator: saved?.locator ?? "", at: saved?.modifiedAt ?? 0 };
      const jump = useBookTransition.getState().takeJump(book.id);
      holdPosition.current = Boolean(jump);
      // Opened at a highlight or note, going back returns to where reading had got to.
      setReturnTo(jump && saved ? (JSON.parse(saved.locator) as Locator) : null);
      setOffer(null);
      await instance.goTo(jump ?? (saved ? (JSON.parse(saved.locator) as Locator) : {}));
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

  // Re-lay out live while the window is resized: at most once a frame, and never two
  // layouts at once; a size change during one is picked up right after it.
  useEffect(() => {
    const el = container.current;
    if (!el) return;
    let frame = 0;
    let busy = false;
    let again = false;
    const run = async () => {
      frame = 0;
      if (busy) return void (again = true);
      busy = true;
      try {
        await renderer.current?.resize();
      } finally {
        busy = false;
        if (again) {
          again = false;
          frame ||= requestAnimationFrame(() => void run());
        }
      }
    };
    const observer = new ResizeObserver(() => {
      frame ||= requestAnimationFrame(() => void run());
    });
    observer.observe(el);
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
    };
  }, [container]);

  // Save the reading position shortly after it settles.
  useEffect(() => {
    if (status.state !== "ready" || !position || holdPosition.current) return;
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
        const page = renderer.current.pageOf(locator);
        setOffer({ locator, label: page ? `Continue on page ${page}?` : `Continue at ${Math.round(remote.percent * 100)}%?` });
      }),
    [book.id],
  );

  // Turns run one after another, but each only waits for the previous page to be laid
  // out, not for its animation, which the next turn cuts short; so pressing a key five
  // times quickly turns five pages and lands on the last without playing them all.
  const turn = useCallback(
    (direction: TurnDirection) => {
      const t = turns.current;
      if (!renderer.current || t.pending >= MAX_QUEUED_TURNS) return t.queue;
      getSelection()?.removeAllRanges();
      holdPosition.current = false;
      t.pending++;
      t.queue = t.queue
        .then(async () => {
          if (renderer.current) await turnPage(renderer.current, direction, latest.current.appearance.settings.pageTurn);
        })
        .catch(console.error)
        .finally(() => t.pending--);
      return t.queue;
    },
    [],
  );

  // Once the offered page is showing, by any route, there's nothing left to offer.
  useEffect(() => {
    if (offer && position && renderer.current?.isVisible(offer.locator)) setOffer(null);
  }, [offer, position]);

  /** Shows a place with a quick fade, without remembering anything. */
  const move = useCallback(async (target: Locator | TocEntry) => {
    const r = renderer.current;
    if (!r) return;
    holdPosition.current = false;
    const fadeOut = r.sheet.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 120, fill: "forwards" });
    await fadeOut.finished;
    if ("label" in target) await r.goToToc(target);
    else await r.goTo(target);
    const fadeIn = r.sheet.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220 });
    fadeOut.cancel();
    await fadeIn.finished;
  }, []);

  /** Goes to a contents entry, or to a highlight, note or bookmark, remembering where reading was for those. */
  const goTo = useCallback(
    async (target: Locator | TocEntry) => {
      const here = renderer.current?.position.locator;
      if (!("label" in target) && here) setReturnTo((first) => first ?? here);
      await move(target);
    },
    [move],
  );

  const goBack = useCallback(() => {
    if (!returnTo) return;
    setReturnTo(null);
    void move(returnTo);
  }, [move, returnTo]);

  const acceptOffer = useCallback(() => {
    if (!offer) return;
    setOffer(null);
    void move(offer.locator);
  }, [offer, move]);

  return { status, position, toc, renderer, turn, goTo, returnTo, goBack, offer, acceptOffer };
}
