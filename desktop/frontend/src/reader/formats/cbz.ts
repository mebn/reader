import JSZip from "jszip";
import type { FixedDocument } from "./types";
import { nameWithoutExtension } from "./dom";

const IMAGE = /\.(jpe?g|png|gif|webp|avif|bmp)$/i;
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

export async function openCbz(data: Blob, fileName: string): Promise<FixedDocument> {
  const zip = await JSZip.loadAsync(data);
  const pages = Object.values(zip.files)
    .filter((f) => !f.dir && IMAGE.test(f.name) && !f.name.startsWith("__MACOSX"))
    .sort((a, b) => collator.compare(a.name, b.name));

  const urls = new Map<number, Promise<string>>();
  const url = (index: number) => {
    if (!urls.has(index)) urls.set(index, pages[index].async("blob").then((b) => URL.createObjectURL(b)));
    return urls.get(index)!;
  };

  const aspects = new Map<number, number>();
  const load = async (index: number) => {
    const img = new Image();
    img.src = await url(index);
    await img.decode().catch(() => undefined);
    aspects.set(index, img.naturalWidth / (img.naturalHeight || 1) || 0.7);
    return img;
  };

  return {
    layout: "fixed",
    metadata: { title: nameWithoutExtension(fileName), author: "" },
    toc: [],
    pageCount: pages.length,
    hasText: false,
    invertInDark: false,

    async pageAspect(index) {
      if (!aspects.has(index)) await load(index);
      return aspects.get(index)!;
    },

    async renderPage(index, target, width, height) {
      const img = await load(index);
      const aspect = aspects.get(index)!;
      const w = Math.min(width, height * aspect);
      Object.assign(img.style, { width: `${w}px`, height: `${w / aspect}px`, display: "block" });
      img.draggable = false;
      target.replaceChildren(img);
    },

    async cover() {
      return pages.length ? pages[0].async("blob") : null;
    },

    destroy() {
      urls.forEach((u) => u.then(URL.revokeObjectURL));
    },
  };
}
