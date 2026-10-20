import { useLocation } from "wouter";
import type { Book } from "@/lib/types";
import { platform } from "@/platform";
import { useAppSettings } from "./use-settings";

/** Opens a book in this window or a new one, following the app setting. */
export function useOpenBook() {
  const [, navigate] = useLocation();
  const [app] = useAppSettings();

  return (book: Book, options: { newWindow?: boolean } = {}) => {
    if (options.newWindow ?? app.openInNewWindow) {
      void platform().openReaderWindow(book);
      return;
    }
    navigate(`/read/${book.id}`);
  };
}
