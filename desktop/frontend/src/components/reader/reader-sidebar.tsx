import { useEffect, useRef } from "react";
import { List } from "lucide-react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { removeAnnotation } from "@/lib/actions";
import type { Annotation, Locator } from "@/lib/types";
import { cn } from "@/lib/utils";
import type { TocEntry } from "@/reader/formats";
import { HIGHLIGHT_COLORS } from "@/reader/text-ranges";
import type { Position } from "@/reader";
import { FloatingPanel } from "./floating-panel";

interface ReaderSidebarProps {
  open: boolean;
  onOpenChange(open: boolean): void;
  toc: TocEntry[];
  annotations: Annotation[];
  position: Position | null;
  onNavigate(target: Locator | TocEntry): void;
}

/**
 * Contents, highlights and bookmarks of the open book, floating over the page. Picking
 * an entry jumps there and keeps the panel open; a press outside closes it.
 */
export function ReaderSidebar({ open, onOpenChange, toc, annotations, position, onNavigate }: ReaderSidebarProps) {
  const highlights = annotations.filter((a) => a.kind === "highlight");
  const bookmarks = annotations.filter((a) => a.kind === "bookmark");
  const go = onNavigate;

  // Each time it opens, the chapter being read is centered rather than the list starting at the top.
  const list = useRef<HTMLUListElement>(null);
  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => list.current?.querySelector("[data-current]")?.scrollIntoView({ block: "center" }));
    return () => cancelAnimationFrame(frame);
  }, [open]);

  return (
    <FloatingPanel open={open} onOpenChange={onOpenChange} label="Contents" hint="Contents and notes" shortcut="contents" icon={<List />} className="h-[min(640px,calc(100vh-var(--titlebar-height)-24px))] w-[360px] sm:max-w-[360px]">
      <Tabs defaultValue="contents" className="flex min-h-0 flex-1 flex-col gap-0">
        <TabsList className="m-3 grid w-auto grid-cols-3">
          <TabsTrigger value="contents">Contents</TabsTrigger>
          <TabsTrigger value="highlights">Notes</TabsTrigger>
          <TabsTrigger value="bookmarks">Bookmarks</TabsTrigger>
        </TabsList>

        <TabsContent value="contents" className="min-h-0 flex-1">
          <ScrollArea className="h-full">
            <ul ref={list} className="px-2 pb-6">
              {toc.map((entry, i) => (
                <li key={i}>
                  <button
                    type="button"
                    onClick={() => go(entry)}
                    data-current={isCurrent(entry, toc, position) || undefined}
                    className={cn(
                      "w-full truncate rounded-md px-3 py-2 text-left text-sm transition-colors hover:bg-accent",
                      isCurrent(entry, toc, position) && "bg-accent font-medium",
                    )}
                    style={{ paddingLeft: 12 + entry.depth * 14 }}
                  >
                    {entry.label}
                  </button>
                </li>
              ))}
              {!toc.length && <Empty />}
            </ul>
          </ScrollArea>
        </TabsContent>

        <TabsContent value="highlights" className="min-h-0 flex-1">
          <ScrollArea className="h-full">
            <ul className="grid gap-1 px-2 pb-6">
              {sortByLocation(highlights).map((a) => (
                <li key={a.id} className="group relative">
                  <button type="button" onClick={() => go(JSON.parse(a.locator))} className="w-full rounded-md px-3 py-2.5 text-left transition-colors hover:bg-accent">
                    <p className="line-clamp-3 border-l-2 pl-2.5 font-serif text-[13px] leading-snug" style={{ borderColor: HIGHLIGHT_COLORS[a.color] }}>
                      {a.text}
                    </p>
                    {a.note && <p className="mt-1.5 line-clamp-3 pl-3 text-xs text-muted-foreground">{a.note}</p>}
                  </button>
                  <RemoveButton onClick={() => removeAnnotation(a)} />
                </li>
              ))}
              {!highlights.length && <Empty />}
            </ul>
          </ScrollArea>
        </TabsContent>

        <TabsContent value="bookmarks" className="min-h-0 flex-1">
          <ScrollArea className="h-full">
            <ul className="grid gap-1 px-2 pb-6">
              {sortByLocation(bookmarks).map((a) => (
                <li key={a.id} className="group relative">
                  <button type="button" onClick={() => go(JSON.parse(a.locator))} className="w-full rounded-md px-3 py-2.5 text-left text-sm transition-colors hover:bg-accent">
                    <div className="truncate">{a.label}</div>
                    <div className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{a.text}</div>
                  </button>
                  <RemoveButton onClick={() => removeAnnotation(a)} />
                </li>
              ))}
              {!bookmarks.length && <Empty />}
            </ul>
          </ScrollArea>
        </TabsContent>
      </Tabs>
    </FloatingPanel>
  );
}

function RemoveButton({ onClick }: { onClick(): void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Remove"
      className="absolute top-2 right-2 rounded px-1.5 text-xs text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 hover:text-destructive focus-visible:opacity-100"
    >
      ×
    </button>
  );
}

function Empty() {
  return <li className="px-3 py-8 text-center text-sm text-muted-foreground">Nothing yet</li>;
}

function locationKey(a: Annotation) {
  const l = JSON.parse(a.locator) as Locator;
  return (l.chapter ?? l.page ?? 0) * 1e7 + (l.start ?? (l.fraction ?? 0) * 1e6);
}

function sortByLocation(list: Annotation[]) {
  return [...list].sort((a, b) => locationKey(a) - locationKey(b));
}

/** The last entry at or before the current position. */
function isCurrent(entry: TocEntry, toc: TocEntry[], position: Position | null) {
  if (!position) return false;
  const here = position.locator;
  const at = (e: TocEntry) => (e.page !== undefined ? e.page <= (here.page ?? 0) : (e.chapter ?? 0) <= (here.chapter ?? 0));
  const current = toc.findLast(at);
  return current === entry;
}
