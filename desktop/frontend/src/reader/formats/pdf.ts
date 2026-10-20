import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import workerUrl from "pdfjs-dist/legacy/build/pdf.worker.min.mjs?url";
import { nameWithoutExtension } from "./dom";
import type { FixedDocument, TocEntry } from "./types";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

type PdfDocument = Awaited<ReturnType<typeof pdfjs.getDocument>["promise"]>;
type OutlineItem = Awaited<ReturnType<PdfDocument["getOutline"]>>[number];

export async function openPdf(data: Blob, fileName: string): Promise<FixedDocument> {
  const loading = pdfjs.getDocument({ data: new Uint8Array(await data.arrayBuffer()) });
  const doc = await loading.promise;
  const info = ((await doc.getMetadata().catch(() => null))?.info ?? {}) as Record<string, string>;
  const toc = await readOutline(doc);

  const aspects = new Map<number, number>();
  const tasks = new WeakMap<HTMLElement, { cancel(): void }>();

  return {
    layout: "fixed",
    metadata: { title: usableTitle(info.Title) || nameWithoutExtension(fileName), author: info.Author?.trim() ?? "" },
    toc,
    pageCount: doc.numPages,
    hasText: true,
    invertInDark: true,

    async pageAspect(index) {
      if (!aspects.has(index)) {
        const vp = (await doc.getPage(index + 1)).getViewport({ scale: 1 });
        aspects.set(index, vp.width / vp.height);
      }
      return aspects.get(index)!;
    },

    async renderPage(index, target, width, height) {
      tasks.get(target)?.cancel();
      const page = await doc.getPage(index + 1);
      const base = page.getViewport({ scale: 1 });
      const scale = Math.min(width / base.width, height / base.height);
      const viewport = page.getViewport({ scale });
      const dpr = window.devicePixelRatio || 1;

      const canvas = document.createElement("canvas");
      canvas.width = Math.floor(viewport.width * dpr);
      canvas.height = Math.floor(viewport.height * dpr);
      Object.assign(canvas.style, { width: `${viewport.width}px`, height: `${viewport.height}px`, display: "block" });
      canvas.dataset.page = "";

      const textLayer = document.createElement("div");
      textLayer.className = "textLayer";
      textLayer.style.setProperty("--scale-factor", String(scale));
      textLayer.style.setProperty("--total-scale-factor", String(scale));

      const task = page.render({ canvas, viewport, transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined });
      tasks.set(target, task);
      try {
        await task.promise;
      } catch (err) {
        if ((err as Error)?.name === "RenderingCancelledException") return;
        throw err;
      }

      const sheet = document.createElement("div");
      Object.assign(sheet.style, { position: "relative", width: `${viewport.width}px`, height: `${viewport.height}px` });
      sheet.append(canvas, textLayer);
      target.replaceChildren(sheet);

      await new pdfjs.TextLayer({ textContentSource: page.streamTextContent(), container: textLayer, viewport }).render();
    },

    async cover() {
      const page = await doc.getPage(1);
      const base = page.getViewport({ scale: 1 });
      const viewport = page.getViewport({ scale: 480 / base.width });
      const canvas = document.createElement("canvas");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      await page.render({ canvas, viewport }).promise;
      return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
    },

    destroy() {
      void loading.destroy();
    },
  };
}

/** PDF titles are often left as the source file name or a tool's default. */
function usableTitle(title: string | undefined) {
  const t = title?.trim() ?? "";
  return /\.[a-z0-9]{2,5}$/i.test(t) || /^(untitled|microsoft word)/i.test(t) ? "" : t;
}

async function readOutline(doc: PdfDocument): Promise<TocEntry[]> {
  const outline = await doc.getOutline().catch(() => null);
  if (!outline) return [];

  const entries: TocEntry[] = [];
  const walk = async (items: OutlineItem[], depth: number) => {
    for (const item of items) {
      const page = await destinationPage(doc, item.dest);
      if (page !== null) entries.push({ label: item.title.trim(), depth, page });
      if (item.items?.length) await walk(item.items, depth + 1);
    }
  };
  await walk(outline, 0);
  return entries;
}

async function destinationPage(doc: PdfDocument, dest: OutlineItem["dest"]): Promise<number | null> {
  try {
    const explicit = typeof dest === "string" ? await doc.getDestination(dest) : dest;
    const ref = explicit?.[0];
    if (ref == null) return null;
    return typeof ref === "number" ? ref : await doc.getPageIndex(ref);
  } catch {
    return null;
  }
}
