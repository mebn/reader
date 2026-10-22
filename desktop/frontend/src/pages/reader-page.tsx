import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation } from "wouter";
import { Page } from "@/components/common/page";
import { AnnotationEditor } from "@/components/reader/annotation-editor";
import { ColorDots } from "@/components/reader/color-dots";
import { Floating } from "@/components/reader/floating";
import { ReaderFooter, ReaderHeader, ReaderJumps } from "@/components/reader/reader-footer";
import { ReaderSettingsPanel } from "@/components/reader/reader-settings-panel";
import { ReaderSidebar } from "@/components/reader/reader-sidebar";
import { ReaderToolbar } from "@/components/reader/reader-toolbar";
import { useReaderEngine } from "@/components/reader/use-reader-engine";
import { Button } from "@/components/ui/button";
import { ContextMenu, ContextMenuContent, ContextMenuItem, ContextMenuSeparator, ContextMenuTrigger } from "@/components/ui/context-menu";
import { saveSettings, useAppSettings, useBookReaderSettings, useDefaultReaderSettings } from "@/hooks/use-settings";
import { useIsDark, useThemeOverride } from "@/hooks/use-theme";
import { addAnnotation, highlightSelection, removeAnnotation } from "@/lib/actions";
import { DEFAULT_READER, resolveBackground, SCOPE, type ReaderSettings } from "@/lib/settings";
import { useShortcuts } from "@/lib/shortcuts";
import type { Book, Locator } from "@/lib/types";
import { platform } from "@/platform";
import type { TextSelection } from "@/reader";
import { useLibrary } from "@/store/library";
import { usePin } from "@/store/pin";
import { useBookTransition } from "@/store/transition";

const CHROME_TIMEOUT = 2500;
const WHEEL_THRESHOLD = 40;
/** Quiet time that ends a scroll gesture. */
const WHEEL_GESTURE_GAP = 250;
/** Scrolls speeding up this much, twice in a row, and at least this fast, start a new swipe. */
const WHEEL_NEW_SWIPE_RATIO = 1.6;
const WHEEL_NEW_SWIPE_MIN = 8;
/** After a turn the wheel stays locked at least this long, about as long as the page takes to turn. */
const WHEEL_MIN_LOCK = 600;
/** Long enough that dragging a slider saves once, at the end. */
const SETTINGS_SAVE_DELAY = 400;

export function ReaderPage({ bookId, standalone = false }: { bookId: string; standalone?: boolean }) {
  const book = useLibrary((s) => s.books[bookId]);
  const ready = useLibrary((s) => s.ready);

  if (!book) {
    return (
      <Page variant="zoom" className="items-center justify-center gap-4">
        {ready && <p className="text-sm text-muted-foreground">This book is no longer in your library.</p>}
      </Page>
    );
  }
  return <ReaderView book={book} standalone={standalone} />;
}

function ReaderView({ book, standalone }: { book: Book; standalone: boolean }) {
  const [, navigate] = useLocation();
  const container = useRef<HTMLDivElement>(null);

  // Appearance: saved settings plus live edits, which are saved to this book shortly after.
  const defaults = useDefaultReaderSettings();
  const { settings: saved, hasOverride } = useBookReaderSettings(book.id);
  const [draft, setDraft] = useState<Partial<ReaderSettings>>({});
  const settings = useMemo(() => ({ ...saved, ...draft }), [saved, draft]);
  const saveForBook = useCallback(
    (next: ReaderSettings) => {
      // Only what differs from the defaults, so the book keeps following the rest.
      const override = Object.fromEntries(Object.entries(next).filter(([k, v]) => defaults[k as keyof ReaderSettings] !== v));
      saveSettings(SCOPE.book(book.id), Object.keys(override).length ? override : null);
    },
    [defaults, book.id],
  );
  useEffect(() => {
    if (!Object.keys(draft).length) return;
    const timer = setTimeout(() => {
      saveForBook(settings);
      setDraft({});
    }, SETTINGS_SAVE_DELAY);
    return () => clearTimeout(timer);
  }, [draft, settings, saveForBook]);
  const [app, setApp] = useAppSettings();
  const dark = useIsDark(app.theme);
  const background = resolveBackground(settings, dark);
  const appearance = useMemo(
    () => ({ settings, dark: background.dark, background: background.color, text: background.text }),
    [settings, background],
  );

  // The window chrome follows the page color.
  const setThemeOverride = useThemeOverride((s) => s.set);
  useEffect(() => setThemeOverride(background.dark ? "dark" : "light"), [background.dark, setThemeOverride]);
  useEffect(() => () => setThemeOverride(null), [setThemeOverride]);

  const allAnnotations = useLibrary((s) => s.annotations);
  const annotations = useMemo(() => Object.values(allAnnotations).filter((a) => a.bookId === book.id), [allAnnotations, book.id]);

  const [editing, setEditing] = useState<{ id: string; rect: DOMRect; focusNote?: boolean } | null>(null);
  const [selection, setSelection] = useState<TextSelection | null>(null);
  // The two floating panels share a spot under the toolbar, so one at a time.
  const [floating, setFloating] = useState<"settings" | "contents" | null>(null);
  const panel = floating === "settings" ? "settings" : null;
  const sidebar = floating === "contents";
  const setPanel = (p: "settings" | null) => setFloating((f) => (p ? p : f === "settings" ? null : f));
  const setSidebar = (open: boolean | ((open: boolean) => boolean)) =>
    setFloating((f) => {
      const next = typeof open === "function" ? open(f === "contents") : open;
      return next ? "contents" : f === "contents" ? null : f;
    });

  const engine = useReaderEngine({
    book,
    container,
    appearance,
    annotations,
    onAnnotationClick: (id, rect) => setEditing({ id, rect }),
    // A press that began while a dialog or popover was open only closes it.
    canInteract: () => !pointerDown.current.dismissing,
  });
  const { position, turn, renderer } = engine;
  /** The place to go back to, named by its page while pages are numbered. */
  const backLabel = (locator: Locator | null) => {
    if (!locator) return null;
    const page = renderer.current?.pageOf(locator);
    return page ? `Back to page ${page}` : "Back";
  };

  // Chrome shows on movement near the top and hides when idle.
  const [chrome, setChrome] = useState(true);
  const chromeTimer = useRef(0);
  const showChrome = useCallback(() => {
    setChrome(true);
    clearTimeout(chromeTimer.current);
    chromeTimer.current = window.setTimeout(() => setChrome(false), CHROME_TIMEOUT);
  }, []);
  useEffect(() => {
    showChrome();
    return () => clearTimeout(chromeTimer.current);
  }, [showChrome]);

  const pinned = usePin((s) => s.pinned);
  const togglePin = usePin((s) => s.toggle);

  useEffect(() => {
    if (standalone) platform().setTitle(book.title);
  }, [standalone, book.title]);

  const close = useCallback(() => {
    if (standalone) return platform().closeWindow();
    useBookTransition.getState().close(book.id);
    navigate(book.folderId ? `/folder/${book.folderId}` : "/");
  }, [standalone, book.id, book.folderId, navigate]);

  // The chapter being read, by the contents' last entry at or before this position.
  const chapterTitle = useMemo(() => {
    if (!position) return undefined;
    const here = position.locator.page ?? position.locator.chapter ?? 0;
    return engine.toc.findLast((e) => (e.page ?? e.chapter ?? 0) <= here)?.label;
  }, [engine.toc, position]);

  // Bookmarks on the visible page(s).
  const bookmark = useMemo(
    () => (position ? annotations.find((a) => a.kind === "bookmark" && renderer.current?.isVisible(JSON.parse(a.locator))) : undefined),
    [annotations, position, renderer],
  );
  const toggleBookmark = () => {
    if (bookmark) return removeAnnotation(bookmark);
    if (!position) return;
    addAnnotation({
      bookId: book.id,
      kind: "bookmark",
      locator: JSON.stringify(position.locator),
      label: chapterTitle ?? book.title,
      text: position.page ? `Page ${position.page}` : `${Math.round(position.percent * 100)}%`,
      note: "",
      color: "",
    });
  };

  const highlight = (color: string, withNote = false, target = selection) => {
    if (!target) return;
    const created = highlightSelection(book.id, annotations, target, color, (locator) => renderer.current?.textOf(locator) ?? null);
    getSelection()?.removeAllRanges();
    setSelection(null);
    setMenu(null);
    if (withNote) setTimeout(() => setEditing({ id: created.id, rect: target.rect, focusNote: true }), 50);
  };

  // Right-click acts on the selection, or on the word under the pointer when nothing is
  // selected, the way Books does. Anywhere else it opens nothing.
  // On an existing highlight it offers to remove or annotate that instead.
  const [menu, setMenu] = useState<{ text: string; selection?: TextSelection; highlight?: { id: string; rect: DOMRect } } | null>(null);
  const onContextMenu = (e: React.MouseEvent) => {
    setSelection(null);
    const hit = renderer.current?.annotationAt(e.clientX, e.clientY);
    const marked = hit ? allAnnotations[hit.id] : undefined;
    if (hit && marked && !marked.deleted) {
      getSelection()?.removeAllRanges();
      return setMenu({ text: marked.text, highlight: hit });
    }
    let sel = renderer.current?.selection() ?? null;
    if (!sel && selectWordAt(e.clientX, e.clientY)) sel = renderer.current?.selection() ?? null;
    if (!sel) return e.preventDefault();
    setMenu({ text: sel.text, selection: sel });
  };
  const searchWeb = (text: string) => platform().openUrl(`https://www.google.com/search?q=${encodeURIComponent(text)}`);

  // Text size from the keyboard is saved right away, to wherever this book's settings live.
  const setFontSize = (size: number) => setDraft((d) => ({ ...d, fontSize: Math.min(34, Math.max(12, size)) }));
  const toggleSettings = () => setFloating((f) => (f === "settings" ? null : "settings"));

  // Keyboard. Capture phase, so these run before popovers handle the key; with a panel,
  // editor or selection open, only the keys that make sense there go through.
  const overlayOpen = panel !== null || editing !== null || selection !== null || menu !== null;
  const reading = !overlayOpen;
  // The reader's own panels are handled above; while any other dialog or menu is open
  // (such as the shortcut list), keys are left to it, Esc included.
  useShortcuts(
    leaveToOtherOverlays({
      next: () => (reading ? void turn("next") : false),
      prev: () => (reading ? void turn("prev") : false),
      // Esc closes the sidebar first, then the book.
      close: () => (!reading ? false : sidebar ? setSidebar(false) : close()),
      bookmark: () => (reading ? toggleBookmark() : false),
      contents: () => (editing || selection ? false : setSidebar((o) => !o)),
      appearance: () => (editing || selection ? false : toggleSettings()),
      settings: () => (editing || selection ? false : toggleSettings()),
      biggerText: () => setFontSize(settings.fontSize + 1),
      smallerText: () => setFontSize(settings.fontSize - 1),
      resetText: () => setFontSize(DEFAULT_READER.fontSize),
      highlight: () => (selection && !editing ? highlight("yellow") : false),
      note: () => (selection && !editing ? highlight("yellow", true) : false),
    }),
    { capture: true, overOverlays: true },
  );

  // One page per gesture. After a turn the wheel stays locked through the trackpad's
  // momentum, which can trickle on for seconds. Momentum only ever slows down, though
  // unevenly, so input that speeds up again twice in a row is a new swipe and unlocks;
  // so does a pause.
  const wheel = useRef({ delta: 0, locked: false, lockedAt: 0, last: 0, slowing: false, rising: 0, timer: 0 });
  const onWheel = (e: React.WheelEvent) => {
    const w = wheel.current;
    const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    const speed = Math.abs(d);
    clearTimeout(w.timer);
    w.timer = window.setTimeout(() => Object.assign(w, { delta: 0, locked: false, last: 0, slowing: false, rising: 0 }), WHEEL_GESTURE_GAP);
    if (w.locked) {
      const rising = speed > w.last * WHEEL_NEW_SWIPE_RATIO && speed >= 1;
      w.rising = rising ? w.rising + 1 : 0;
      // Only once this swipe is past its peak: while a finger is still speeding up, it isn't new.
      const newSwipe = w.slowing && w.rising >= 2 && speed > WHEEL_NEW_SWIPE_MIN && performance.now() - w.lockedAt > WHEEL_MIN_LOCK;
      if (speed < w.last) w.slowing = true;
      w.last = speed;
      if (!newSwipe) return;
      Object.assign(w, { delta: 0, locked: false, slowing: false, rising: 0 });
    }
    w.last = speed;
    w.delta += d;
    if (Math.abs(w.delta) < WHEEL_THRESHOLD) return;
    const direction = w.delta > 0 ? "next" : "prev";
    Object.assign(w, { delta: 0, locked: true, lockedAt: performance.now(), slowing: false, rising: 0 });
    void turn(direction);
  };

  // Clicks: left third back, right third forward, middle toggles the chrome.
  // A press that closes a menu or popover only closes it; it doesn't turn the page too.
  const pointerDown = useRef({ x: 0, y: 0, dismissing: false });

  // Whether the press closes something is decided before anything reacts to it: panels
  // close themselves on the same press, and React re-renders before the page sees it.
  const anyOpen = useRef(false);
  anyOpen.current = overlayOpen || floating !== null;
  useEffect(() => {
    const press = () => (pointerDown.current.dismissing = anyOpen.current || menuOpen());
    window.addEventListener("pointerdown", press, true);
    return () => window.removeEventListener("pointerdown", press, true);
  }, []);
  const onPointerUp = (e: React.PointerEvent) => {
    const moved = Math.hypot(e.clientX - pointerDown.current.x, e.clientY - pointerDown.current.y) > 4;
    if (e.button !== 0) return;
    if (pointerDown.current.dismissing) {
      // A drag still selects, so a new passage can be picked while the last one's menu
      // shows; only a plain press is spent on closing.
      if (moved) requestAnimationFrame(() => setSelection(renderer.current?.selection() ?? null));
      return;
    }
    requestAnimationFrame(() => {
      const sel = renderer.current?.selection() ?? null;
      if (sel) return setSelection(sel);
      if (moved || e.button !== 0) return;
      const target = e.target as HTMLElement;
      if (target.closest("a[data-href], a[data-external]") || renderer.current?.annotationAt(e.clientX, e.clientY)) return;
      const x = e.clientX / window.innerWidth;
      if (x < 0.3) void turn("prev");
      else if (x > 0.7) void turn("next");
      else if (chrome) setChrome(false);
      else showChrome();
    });
  };

  const clock = useClock(settings.headerClock);
  const headerText =
    [settings.headerTitle && book.title, settings.headerAuthor && book.author, settings.headerChapter && chapterTitle, settings.headerClock && clock]
      .filter(Boolean)
      .join("  ·  ") || undefined;
  const editingAnnotation = editing ? allAnnotations[editing.id] : undefined;
  const ready = engine.status.state === "ready";

  // The traffic lights come and go with the toolbar.
  const chromeVisible = chrome || floating !== null || !ready;
  useEffect(() => platform().setWindowButtonsVisible(chromeVisible), [chromeVisible]);
  useEffect(() => () => platform().setWindowButtonsVisible(true), []);

  return (
    <Page
      variant="fade"
      style={{ background: background.color, "--reader-fg": background.text } as React.CSSProperties}
      onMouseMove={(e) => e.clientY < 90 && showChrome()}
    >
      <ReaderToolbar
        visible={chromeVisible}
        title={headerText}
        bookmarked={Boolean(bookmark)}
        pinned={pinned}
        onClose={standalone ? undefined : close}
        contents={
          <ReaderSidebar open={sidebar} onOpenChange={setSidebar} toc={engine.toc} annotations={annotations} position={position} onNavigate={(target) => void engine.goTo(target)} />
        }
        onBookmark={toggleBookmark}
        onPin={() => void togglePin()}
        settings={
          <ReaderSettingsPanel
            open={panel === "settings"}
            onOpenChange={(open) => setPanel(open ? "settings" : null)}
            value={settings}
            dark={dark}
            onModeChange={(mode) => setApp({ theme: mode })}
            hasOverride={hasOverride || Object.keys(draft).length > 0}
            fixed={book.format === "pdf" || book.format === "cbz"}
            onChange={(patch) => setDraft((d) => ({ ...d, ...patch }))}
            onMakeDefault={() => {
              saveSettings(SCOPE.reader, settings);
              saveSettings(SCOPE.book(book.id), null);
              setDraft({});
            }}
            onReset={() => {
              saveSettings(SCOPE.book(book.id), null);
              setDraft({});
            }}
          />
        }
      />

      {/* The page, with its running header and footer. */}
      <div className="relative flex min-h-0 flex-1 flex-col">
          <ContextMenu onOpenChange={(open) => !open && setMenu(null)}>
            <ContextMenuTrigger asChild>
              <div
                ref={container}
                className="relative min-h-0 flex-1 overflow-hidden"
                style={{ opacity: ready ? 1 : 0, transition: "opacity 300ms" }}
                onWheel={onWheel}
                onPointerDown={(e) => Object.assign(pointerDown.current, { x: e.clientX, y: e.clientY })}
                onPointerUp={onPointerUp}
                onContextMenu={onContextMenu}
              />
            </ContextMenuTrigger>
            <ContextMenuContent className="w-52">
              {menu?.highlight ? (
                <>
                  <ContextMenuItem
                    variant="destructive"
                    onSelect={() => {
                      const marked = allAnnotations[menu.highlight!.id];
                      if (marked) removeAnnotation(marked);
                    }}
                  >
                    Remove highlight
                  </ContextMenuItem>
                  <ContextMenuItem onSelect={() => setTimeout(() => setEditing({ ...menu.highlight!, focusNote: true }), 50)}>
                    {allAnnotations[menu.highlight.id]?.note ? "Edit note" : "Add note"}
                  </ContextMenuItem>
                </>
              ) : (
                <>
                  <ContextMenuItem onSelect={() => highlight("yellow", false, menu?.selection)}>Highlight</ContextMenuItem>
                  <ContextMenuItem onSelect={() => highlight("yellow", true, menu?.selection)}>Highlight with note</ContextMenuItem>
                </>
              )}
              <ContextMenuSeparator />
              <ContextMenuItem onSelect={() => menu && searchWeb(menu.text)}>
                <span className="truncate">Search Google for “{truncate(menu?.text ?? "", 24)}”</span>
              </ContextMenuItem>
            </ContextMenuContent>
          </ContextMenu>

          <ReaderHeader text={ready ? headerText : undefined} hidden={chromeVisible} />
          <ReaderFooter position={ready ? position : null} chapter={chapterTitle} settings={settings} />
          {ready && (
            <ReaderJumps
              back={backLabel(engine.returnTo)}
              offer={engine.offer?.label ?? null}
              onBack={engine.goBack}
              onContinue={engine.acceptOffer}
            />
          )}

          {engine.status.state === "error" && (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-4">
              <p className="max-w-sm text-center text-sm text-[color:var(--reader-fg)] opacity-70">Couldn't open this book. {engine.status.message}</p>
              <Button variant="outline" size="sm" onClick={close}>
                Close
              </Button>
            </div>
          )}
      </div>

      <Floating rect={selection?.rect ?? null} onClose={() => setSelection(null)}>
        <div className="flex items-center gap-2 px-1">
          <ColorDots onPick={(color) => highlight(color)} />
          <div className="h-5 w-px bg-border" />
          <Button variant="ghost" size="xs" onClick={() => highlight("yellow", true)}>
            Note
          </Button>
        </div>
      </Floating>

      <Floating rect={editingAnnotation ? editing!.rect : null} onClose={() => setEditing(null)}>
        {editingAnnotation && <AnnotationEditor annotation={editingAnnotation} focusNote={editing?.focusNote} onDone={() => setEditing(null)} />}
      </Floating>


    </Page>
  );
}

function truncate(text: string, max: number) {
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

/** Selects the word under a point in the book's text; false when there is none. */
function selectWordAt(x: number, y: number) {
  const caret = document.caretRangeFromPoint(x, y);
  const node = caret?.startContainer;
  if (!caret || node?.nodeType !== Node.TEXT_NODE || !node.parentElement?.closest(".book-content, .textLayer")) return false;
  const sel = getSelection();
  if (!sel) return false;
  sel.setPosition(node, caret.startOffset);
  sel.modify("move", "backward", "word");
  sel.modify("extend", "forward", "word");
  if (!sel.toString().trim()) {
    sel.removeAllRanges();
    return false;
  }
  return true;
}

const timeFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });

/** The time of day, kept current to the minute while it's wanted. */
function useClock(enabled: boolean) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!enabled) return;
    setNow(Date.now());
    let timer = 0;
    const tick = () => {
      setNow(Date.now());
      timer = window.setTimeout(tick, 60_000 - (Date.now() % 60_000));
    };
    timer = window.setTimeout(tick, 60_000 - (Date.now() % 60_000));
    return () => clearTimeout(timer);
  }, [enabled]);
  return timeFormat.format(now);
}

/** Whether any menu or dialog is showing, so a press on the page only closes it. */
function menuOpen() {
  return Boolean(document.querySelector('[role="menu"][data-state="open"], [role="dialog"][data-state="open"]'));
}

/** Whether a dialog or menu other than the reader's own floating panels is showing. */
function otherOverlayOpen() {
  return Boolean(document.querySelector('[role="menu"][data-state="open"], [role="dialog"][data-state="open"]:not([data-floating-panel])'));
}

/** Wraps shortcut handlers so they stand aside while another dialog or menu is open. */
function leaveToOtherOverlays<T extends Record<string, (e: KeyboardEvent) => boolean | void>>(handlers: T): T {
  return Object.fromEntries(Object.entries(handlers).map(([id, fn]) => [id, (e: KeyboardEvent) => (otherOverlayOpen() ? false : fn(e))])) as T;
}
