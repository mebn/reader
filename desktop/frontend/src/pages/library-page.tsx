import { useCallback, useMemo, useRef } from "react";
import { ChevronDown, ChevronLeft, Pin, Search, Settings } from "lucide-react";
import { motion } from "motion/react";
import { Link, useLocation, useParams } from "wouter";
import { Hint } from "@/components/common/hint";
import { Page } from "@/components/common/page";
import { WindowHeader } from "@/components/common/window-header";
import { AddMenu } from "@/components/library/add-menu";
import { AnnotationList, useAnnotationGroups } from "@/components/library/annotation-list";
import { Breadcrumbs } from "@/components/library/breadcrumbs";
import { ContinueReading, useLastRead } from "@/components/library/continue-reading";
import { FileDropZone } from "@/components/library/file-drop-zone";
import { LibraryGrid } from "@/components/library/library-grid";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { useAppSettings } from "@/hooks/use-settings";
import { useLibraryView, type LibraryView } from "@/hooks/use-library-view";
import { LIBRARY_TABS } from "@/lib/settings";
import { useShortcuts } from "@/lib/shortcuts";
import type { Book } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useLibrary } from "@/store/library";
import { useLibraryFilter, type LibraryTab } from "@/store/library-filter";
import { usePin } from "@/store/pin";

export function LibraryPage() {
  const { folderId = null } = useParams<{ folderId?: string }>();
  const view = useLibraryView(folderId);
  const ready = useLibrary((s) => s.ready);
  const [app] = useAppSettings();
  const { tab: picked, query, setTab, setQuery } = useLibraryFilter();
  // Inside a folder there are no tabs: just its books and subfolders.
  const tab = folderId ? "books" : (picked ?? app.defaultTab);
  const [, navigate] = useLocation();
  const parent = view.path.at(-2);
  const goUp = () => navigate(parent ? `/folder/${parent.id}` : "/");
  const searchRef = useRef<HTMLInputElement>(null);

  useShortcuts({
    search: () => searchRef.current?.focus(),
    back: (e) => {
      // Escape in the search box clears it first, then leaves it.
      if (e.target === searchRef.current) {
        if (query) setQuery("");
        else searchRef.current?.blur();
        return;
      }
      if (!folderId) return false;
      goUp();
    },
  });

  const inScope = useInFolder(folderId);
  const shown = useSearchedView(view, query);
  // In All, each kind gets its own section, and a highlight with a note shows only under Notes.
  const sections = {
    highlights: useAnnotationGroups(tab === "all" ? "plain" : "highlights", query, inScope),
    notes: useAnnotationGroups("notes", query, inScope),
    bookmarks: useAnnotationGroups("bookmarks", query, inScope),
  };
  const shownSections = (["highlights", "notes", "bookmarks"] as const).filter((k) => tab === "all" || tab === k);
  const anyNotes = shownSections.some((k) => sections[k].length > 0);

  const showBooks = tab === "all" || tab === "books";
  const lastRead = useLastRead(inScope);
  const noBooks = !shown.folders.length && !shown.books.length;

  return (
    <Page>
      <WindowHeader
        left={<Breadcrumbs path={view.path} />}
        right={
          <>
            <AddMenu folderId={folderId} />
            <PinButton />
            <Hint label="Settings" shortcut="settings">
              <Button variant="ghost" size="icon-sm" aria-label="Settings" asChild>
                <Link href="/settings">
                  <Settings className="size-[17px]" />
                </Link>
              </Button>
            </Hint>
          </>
        }
      />
      {/* Back (in a folder) · tabs, centered · search. */}
      <div className="mx-auto grid w-full max-w-[1400px] grid-cols-[1fr_auto_1fr] items-center gap-3 px-8 pt-1 pb-3">
        <div>
          {folderId && (
            <Hint label={`Back to ${parent?.name ?? "Library"}`} shortcut="back">
              <Button variant="outline" size="sm" className="h-8 gap-1 pr-3 pl-2 text-xs" onClick={goUp}>
                <ChevronLeft className="size-4" />
                {parent?.name ?? "Library"}
              </Button>
            </Hint>
          )}
        </div>
        <div>
          {!folderId && (
            <>
              <ToggleGroup type="single" variant="outline" size="sm" value={tab} onValueChange={(v) => v && setTab(v as LibraryTab)} className="max-[640px]:hidden">
                {LIBRARY_TABS.map(([value, label]) => (
                  <ToggleGroupItem key={value} value={value} className="px-3 text-xs">
                    {label}
                  </ToggleGroupItem>
                ))}
              </ToggleGroup>
              {/* Too narrow for the tabs and a search box side by side: the tabs fold into a menu. */}
              <TabMenu tab={tab} onChange={setTab} />
            </>
          )}
        </div>
        <div className="relative w-full max-w-60 min-w-36 justify-self-end">
          <Search className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <Input ref={searchRef} value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search" className="h-8 pl-8 text-sm" />
        </div>
      </div>
      <FileDropZone folderId={folderId}>
        <ScrollArea className="min-h-0 flex-1">
          {/* Switching tabs and moving between folders are both instant. */}
          <div className="mx-auto grid max-w-[1400px] gap-12 px-8 pt-4 pb-16">
            {showBooks && !folderId && !query.trim() && lastRead && <ContinueReading {...lastRead} />}

            {showBooks && (
              <section>
                {tab === "all" && !noBooks && <SectionTitle>Books</SectionTitle>}
                {noBooks ? ready && !(tab === "all" && anyNotes) && <Empty text={query ? "No books match" : "Drop books here"} /> : <LibraryGrid view={shown} />}
              </section>
            )}

            {shownSections.map(
              (kind) =>
                sections[kind].length > 0 && (
                  <section key={kind}>
                    {tab === "all" && <SectionTitle>{SECTION_TITLES[kind]}</SectionTitle>}
                    <AnnotationList groups={sections[kind]} />
                  </section>
                ),
            )}
            {tab !== "all" && tab !== "books" && !anyNotes && ready && (
              <Empty text={query ? "Nothing matches" : `Your ${tab} from ${folderId ? "books in this folder" : "your books"} show up here`} />
            )}
          </div>
        </ScrollArea>
      </FileDropZone>
    </Page>
  );
}

/** Whether a book is in a folder or any folder inside it; everything at the root. */
function useInFolder(folderId: string | null) {
  const folders = useLibrary((s) => s.folders);
  const ids = useMemo(() => {
    if (!folderId) return null;
    const set = new Set([folderId]);
    // Folders are few; repeat until no new descendants turn up.
    for (let grew = true; grew; ) {
      grew = false;
      for (const f of Object.values(folders)) {
        if (f.parentId && set.has(f.parentId) && !set.has(f.id)) {
          set.add(f.id);
          grew = true;
        }
      }
    }
    return set;
  }, [folderId, folders]);
  return useCallback((book: Book) => !ids || (book.folderId !== null && ids.has(book.folderId)), [ids]);
}

/**
 * With a search: from the top of the library, every matching book and folder anywhere;
 * inside a folder, only that folder's own books and subfolders.
 */
function useSearchedView(view: LibraryView, query: string): LibraryView {
  const books = useLibrary((s) => s.books);
  const folders = useLibrary((s) => s.folders);
  return useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return view;
    const bookMatches = (b: Book) => b.title.toLowerCase().includes(q) || b.author.toLowerCase().includes(q);
    if (view.folder) {
      return { ...view, folders: view.folders.filter((f) => f.name.toLowerCase().includes(q)), books: view.books.filter(bookMatches) };
    }
    const matchingFolders = Object.values(folders).filter((f) => !f.deleted && f.name.toLowerCase().includes(q));
    const folderBooks: Record<string, Book[]> = {};
    for (const f of matchingFolders) folderBooks[f.id] = Object.values(books).filter((b) => b.folderId === f.id);
    return {
      ...view,
      folders: matchingFolders,
      books: Object.values(books).filter((b) => !b.deleted && bookMatches(b)),
      folderBooks,
    };
  }, [view, query, books, folders]);
}

function TabMenu({ tab, onChange }: { tab: LibraryTab; onChange(tab: LibraryTab): void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="h-8 gap-1 pr-2 pl-3 text-xs min-[641px]:hidden">
          {LIBRARY_TABS.find(([value]) => value === tab)?.[1]}
          <ChevronDown className="size-3.5 opacity-60" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="center" className="w-40">
        <DropdownMenuRadioGroup value={tab} onValueChange={(v) => onChange(v as LibraryTab)}>
          {LIBRARY_TABS.map(([value, label]) => (
            <DropdownMenuRadioItem key={value} value={value}>
              {label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Keeps the window above others; the same pin as in the reader. */
function PinButton() {
  const pinned = usePin((s) => s.pinned);
  const toggle = usePin((s) => s.toggle);
  return (
    <Hint label={pinned ? "Stop keeping on top" : "Keep window on top"} shortcut="pin">
      <Button variant="ghost" size="icon-sm" aria-label="Keep on top" aria-pressed={pinned} onClick={() => void toggle()}>
        <Pin className={cn("size-[17px] transition-transform", pinned && "rotate-45 fill-current")} />
      </Button>
    </Hint>
  );
}

const SECTION_TITLES = { highlights: "Highlights", notes: "Notes", bookmarks: "Bookmarks" };

function SectionTitle({ children }: { children: string }) {
  return <h2 className="mb-5 text-xs font-medium tracking-wide text-muted-foreground uppercase">{children}</h2>;
}

function Empty({ text }: { text: string }) {
  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.1 }} className="flex h-[50vh] items-center justify-center">
      <p className="text-sm text-muted-foreground">{text}</p>
    </motion.div>
  );
}
