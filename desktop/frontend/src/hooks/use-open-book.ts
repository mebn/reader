import { useLocation } from "wouter";
import type { Book } from "@/lib/types";
import { platform } from "@/platform";
import { useBookTransition } from "@/store/transition";
import { useAppSettings } from "./use-settings";

/** Opens a book in this window or a new one, following the app setting. */
export function useOpenBook() {
  const [, navigate] = useLocation();
  const [app] = useAppSettings();
  const open = useBookTransition((s) => s.open);

  return (book: Book, options: { rect?: DOMRect; newWindow?: boolean } = {}) => {
    if (options.newWindow ?? app.openInNewWindow) {
      void platform().openReaderWindow(book);
      return;
    }
    if (options.rect) open(book.id, options.rect);
    navigate(`/read/${book.id}`);
  };
}
