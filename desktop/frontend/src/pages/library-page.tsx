import { Settings } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { Link, useParams } from "wouter";
import { Page } from "@/components/common/page";
import { WindowHeader } from "@/components/common/window-header";
import { AddMenu } from "@/components/library/add-menu";
import { Breadcrumbs } from "@/components/library/breadcrumbs";
import { FileDropZone } from "@/components/library/file-drop-zone";
import { LibraryGrid } from "@/components/library/library-grid";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useLibraryView } from "@/hooks/use-library-view";
import { useLibrary } from "@/store/library";

export function LibraryPage() {
  const { folderId = null } = useParams<{ folderId?: string }>();
  const view = useLibraryView(folderId);
  const ready = useLibrary((s) => s.ready);
  const empty = !view.folders.length && !view.books.length;

  return (
    <Page>
      <WindowHeader
        left={<Breadcrumbs path={view.path} />}
        right={
          <>
            <AddMenu folderId={folderId} />
            <Button variant="ghost" size="icon-sm" aria-label="Settings" asChild>
              <Link href="/settings">
                <Settings className="size-[17px]" />
              </Link>
            </Button>
          </>
        }
      />
      <FileDropZone folderId={folderId}>
        <ScrollArea className="min-h-0 flex-1">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={folderId ?? "root"}
              initial={{ opacity: 0, x: 12 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -12 }}
              transition={{ duration: 0.22, ease: [0.32, 0.72, 0, 1] }}
              className="mx-auto max-w-[1400px] px-8 pt-4 pb-16"
            >
              {ready && empty ? <EmptyState /> : <LibraryGrid view={view} />}
            </motion.div>
          </AnimatePresence>
        </ScrollArea>
      </FileDropZone>
    </Page>
  );
}

function EmptyState() {
  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.1 }} className="flex h-[60vh] items-center justify-center">
      <p className="text-sm text-muted-foreground">Drop books here</p>
    </motion.div>
  );
}
