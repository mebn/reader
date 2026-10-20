import type { Format } from "@/lib/types";
import type { BookDocument, BookMetadata } from "./types";

export type { BookDocument, FixedDocument, ReflowDocument, TocEntry } from "./types";

/** Parsers are loaded on demand so the library view stays light. */
export async function openDocument(data: Blob, format: Format, fileName: string): Promise<BookDocument> {
  switch (format) {
    case "epub":
      return (await import("./epub")).openEpub(data);
    case "pdf":
      return (await import("./pdf")).openPdf(data, fileName);
    case "fb2":
      return (await import("./fb2")).openFb2(data, fileName);
    case "cbz":
      return (await import("./cbz")).openCbz(data, fileName);
    case "txt":
      return (await import("./txt")).openTxt(data, fileName);
  }
}

export interface BookInfo extends BookMetadata {
  cover: Blob | null;
}

/** Reads title, author and cover for import. */
export async function readBookInfo(data: Blob, format: Format, fileName: string): Promise<BookInfo> {
  const doc = await openDocument(data, format, fileName);
  try {
    const cover = await doc.cover().catch(() => null);
    return { ...doc.metadata, cover };
  } finally {
    doc.destroy();
  }
}
