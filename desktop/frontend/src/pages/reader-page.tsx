import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation } from "wouter";
import { Page } from "@/components/common/page";
import { AnnotationEditor } from "@/components/reader/annotation-editor";
import { ColorDots } from "@/components/reader/color-dots";
import { Floating } from "@/components/reader/floating";
import { OpeningCover } from "@/components/reader/opening-cover";
import { ReaderFooter } from "@/components/reader/reader-footer";
import { ReaderSettingsPanel } from "@/components/reader/reader-settings-panel";
import { ReaderSidebar } from "@/components/reader/reader-sidebar";
import { ReaderToolbar } from "@/components/reader/reader-toolbar";
import { useReaderEngine } from "@/components/reader/use-reader-engine";
import { Button } from "@/components/ui/button";
import { saveSettings, useBookReaderSettings } from "@/hooks/use-settings";
import { useIsDark, useThemeOverride } from "@/hooks/use-theme";
import { addAnnotation, removeAnnotation } from "@/lib/actions";
import { resolveBackground, SCOPE, type ReaderSettings } from "@/lib/settings";
import type { Book } from "@/lib/types";
import { platform } from "@/platform";
import type { TextSelection } from "@/reader";
import { useLibrary } from "@/store/library";
import { useBookTransition } from "@/store/transition";

const CHROME_TIMEOUT = 2500;
const WHEEL_THRESHOLD = 40;

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

  // Appearance: saved settings plus unsaved live edits.
  const { settings: saved, hasOverride } = useBookReaderSettings(book.id);
  const [draft, setDraft] = useState<Partial<ReaderSettings>>({});
  const settings = useMemo(() => ({ ...saved, ...draft }), [saved, draft]);
  const dirty = Object.entries(draft).some(([k, v]) => saved[k as keyof ReaderSettings] !== v);
  const dark = useIsDark(settings.theme);
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
  const [panel, setPanel] = useState<"settings" | "sidebar" | null>(null);

  const engine = useReaderEngine({
    book,
    container,
    appearance,
    annotations,
    onAnnotationClick: (id, rect) => setEditing({ id, rect }),
  });
  const { position, turn, renderer } = engine;

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

  const [pinned, setPinned] = useState(false);
  const togglePin = async () => setPinned(await platform().setPinned(!pinned));
  useEffect(() => () => void platform().setPinned(false), []);

  useEffect(() => {
    if (standalone) platform().setTitle(book.title);
  }, [standalone, book.title]);

  const close = useCallback(() => {
    if (standalone) return platform().closeWindow();
    useBookTransition.getState().close(book.id);
    navigate(book.folderId ? `/folder/${book.folderId}` : "/");
  }, [standalone, book.id, book.folderId, navigate]);

  // Bookmarks on the visible page(s).
  const bookmark = useMemo(
    () => (position ? annotations.find((a) => a.kind === "bookmark" && renderer.current?.isVisible(JSON.parse(a.locator))) : undefined),
    [annotations, position, renderer],
  );
  const toggleBookmark = () => {
    if (bookmark) return removeAnnotation(bookmark);
    if (!position) return;
    const chapter = engine.toc.findLast((e) => (e.page ?? e.chapter ?? 0) <= (position.locator.page ?? position.locator.chapter ?? 0));
    addAnnotation({
      bookId: book.id,
      kind: "bookmark",
      locator: JSON.stringify(position.locator),
      label: chapter?.label ?? book.title,
      text: position.page ? `Page ${position.page}` : `${Math.round(position.percent * 100)}%`,
      note: "",
      color: "",
    });
  };

  const highlight = (color: string, withNote = false) => {
    if (!selection) return;
    const created = addAnnotation({ bookId: book.id, kind: "highlight", locator: JSON.stringify(selection.locator), text: selection.text, note: "", color, label: "" });
    getSelection()?.removeAllRanges();
    setSelection(null);
    if (withNote) setTimeout(() => setEditing({ id: created.id, rect: selection.rect, focusNote: true }), 50);
  };

  // Keyboard and wheel navigation.
  const overlayOpen = panel !== null || editing !== null || selection !== null;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (overlayOpen || (e.target as HTMLElement).closest("input, textarea")) return;
      if (["ArrowRight", "PageDown"].includes(e.key) || (e.key === " " && !e.shiftKey)) void turn("next");
      else if (["ArrowLeft", "PageUp"].includes(e.key) || (e.key === " " && e.shiftKey)) void turn("prev");
      else if (e.key === "Escape") close();
      else return;
      e.preventDefault();
    };
    // Capture phase: runs before popovers handle the key, so Escape closes them, not the book.
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [overlayOpen, turn, close]);

  const wheel = useRef({ delta: 0, locked: false });
  const onWheel = (e: React.WheelEvent) => {
    if (wheel.current.locked) return;
    wheel.current.delta += Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    if (Math.abs(wheel.current.delta) < WHEEL_THRESHOLD) return;
    const direction = wheel.current.delta > 0 ? "next" : "prev";
    wheel.current = { delta: 0, locked: true };
    void turn(direction).finally(() => setTimeout(() => (wheel.current.locked = false), 120));
  };

  // Clicks: left third back, right third forward, middle toggles the chrome.
  const pointerDown = useRef({ x: 0, y: 0 });
  const onPointerUp = (e: React.PointerEvent) => {
    const moved = Math.hypot(e.clientX - pointerDown.current.x, e.clientY - pointerDown.current.y) > 4;
    requestAnimationFrame(() => {
      const sel = renderer.current?.selection() ?? null;
      if (sel) return setSelection(sel);
      if (moved || e.button !== 0) return;
      const target = e.target as HTMLElement;
      if (target.closest("mark, a[data-href], a[data-external]")) return;
      const x = e.clientX / window.innerWidth;
      if (x < 0.3) void turn("prev");
      else if (x > 0.7) void turn("next");
      else if (chrome) setChrome(false);
      else showChrome();
    });
  };

  const editingAnnotation = editing ? allAnnotations[editing.id] : undefined;
  const ready = engine.status.state === "ready";

  return (
    <Page
      variant="zoom"
      className="transition-colors duration-300"
      style={{ background: background.color, "--reader-fg": background.text } as React.CSSProperties}
      onMouseMove={(e) => e.clientY < 90 && showChrome()}
    >
      <ReaderToolbar
        visible={chrome || panel !== null || !ready}
        title={book.title}
        bookmarked={Boolean(bookmark)}
        pinned={pinned}
        onClose={close}
        onContents={() => setPanel("sidebar")}
        onBookmark={toggleBookmark}
        onPin={() => void togglePin()}
        settings={
          <ReaderSettingsPanel
            open={panel === "settings"}
            onOpenChange={(open) => setPanel(open ? "settings" : null)}
            value={settings}
            dirty={dirty}
            hasOverride={hasOverride}
            onChange={(patch) => setDraft((d) => ({ ...d, ...patch }))}
            onSaveBook={() => {
              saveSettings(SCOPE.book(book.id), settings);
              setDraft({});
            }}
            onSaveDefault={() => {
              saveSettings(SCOPE.reader, settings);
              if (hasOverride) saveSettings(SCOPE.book(book.id), null);
              setDraft({});
            }}
            onReset={() => saveSettings(SCOPE.book(book.id), null)}
          />
        }
      />

      <div
        ref={container}
        className="relative min-h-0 flex-1 overflow-hidden"
        style={{ opacity: ready ? 1 : 0, transition: "opacity 300ms" }}
        onWheel={onWheel}
        onPointerDown={(e) => (pointerDown.current = { x: e.clientX, y: e.clientY })}
        onPointerUp={onPointerUp}
      />

      <ReaderFooter position={ready ? position : null} />

      {engine.status.state === "error" && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4">
          <p className="max-w-sm text-center text-sm text-[color:var(--reader-fg)] opacity-70">Couldn't open this book. {engine.status.message}</p>
          <Button variant="outline" size="sm" onClick={close}>
            Close
          </Button>
        </div>
      )}

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

      <ReaderSidebar
        open={panel === "sidebar"}
        onOpenChange={(open) => setPanel(open ? "sidebar" : null)}
        toc={engine.toc}
        annotations={annotations}
        position={position}
        onNavigate={(target) => void engine.goTo(target)}
      />

      <OpeningCover book={book} ready={ready} />
    </Page>
  );
}
