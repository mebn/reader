import { AnimatePresence } from "motion/react";
import type { LibraryView } from "@/hooks/use-library-view";
import { BookCard } from "./book-card";
import { FolderCard } from "./folder-card";

/** Folders first, then books, in a responsive grid of covers. */
export function LibraryGrid({ view }: { view: LibraryView }) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(132px,1fr))] gap-x-6 gap-y-8 lg:grid-cols-[repeat(auto-fill,minmax(150px,1fr))]">
      <AnimatePresence mode="popLayout" initial={false}>
        {view.folders.map((folder) => (
          <FolderCard key={folder.id} folder={folder} books={view.folderBooks[folder.id] ?? []} />
        ))}
        {view.books.map((book) => (
          <BookCard key={book.id} book={book} />
        ))}
      </AnimatePresence>
    </div>
  );
}
