import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { removeAnnotation } from "@/lib/actions";
import type { Annotation, Locator } from "@/lib/types";
import { cn } from "@/lib/utils";
import type { TocEntry } from "@/reader/formats";
import { HIGHLIGHT_COLORS } from "@/reader/text-ranges";
import type { Position } from "@/reader";

interface ReaderSidebarProps {
  open: boolean;
  toc: TocEntry[];
  annotations: Annotation[];
  position: Position | null;
  onOpenChange(open: boolean): void;
  onNavigate(target: Locator | TocEntry): void;
}

/** Contents, highlights and bookmarks of the open book. */
export function ReaderSidebar({ open, toc, annotations, position, onOpenChange, onNavigate }: ReaderSidebarProps) {
  const highlights = annotations.filter((a) => a.kind === "highlight");
  const bookmarks = annotations.filter((a) => a.kind === "bookmark");
  const go = (target: Locator | TocEntry) => {
    onOpenChange(false);
    onNavigate(target);
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="w-[340px] gap-0 p-0 sm:max-w-[340px]" showCloseButton={false}>
        <SheetTitle className="sr-only">Contents</SheetTitle>
        <Tabs defaultValue="contents" className="flex h-full min-h-0 flex-col gap-0">
          <TabsList className="m-3 grid w-auto grid-cols-3">
            <TabsTrigger value="contents">Contents</TabsTrigger>
            <TabsTrigger value="highlights">Notes</TabsTrigger>
            <TabsTrigger value="bookmarks">Bookmarks</TabsTrigger>
          </TabsList>

          <TabsContent value="contents" className="min-h-0 flex-1">
            <ScrollArea className="h-full">
              <ul className="px-2 pb-6">
                {toc.map((entry, i) => (
                  <li key={i}>
                    <button
                      type="button"
                      onClick={() => go(entry)}
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
      </SheetContent>
    </Sheet>
  );
}

function RemoveButton({ onClick }: { onClick(): void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Remove"
      className="absolute top-2 right-2 rounded px-1.5 text-xs text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 hover:text-destructive"
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
