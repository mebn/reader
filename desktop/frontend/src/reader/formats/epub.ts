import JSZip from "jszip";
import { isExternal, parseXml, resolvePath, sanitize, textOf, toFragment } from "./dom";
import type { ReflowDocument, TocEntry } from "./types";

interface ManifestItem {
  id: string;
  path: string;
  type: string;
  properties: string;
}

export async function openEpub(data: Blob): Promise<ReflowDocument> {
  const zip = await JSZip.loadAsync(data);
  const readText = async (path: string) => {
    const file = zip.file(path);
    if (!file) throw new Error(`missing ${path}`);
    return file.async("string");
  };

  const container = parseXml(await readText("META-INF/container.xml"));
  const opfPath = container.getElementsByTagNameNS("*", "rootfile")[0]?.getAttribute("full-path");
  if (!opfPath) throw new Error("not an EPUB");
  const opf = parseXml(await readText(opfPath));

  const manifest = new Map<string, ManifestItem>();
  for (const el of Array.from(opf.getElementsByTagNameNS("*", "item"))) {
    const href = el.getAttribute("href");
    if (!href) continue;
    manifest.set(el.getAttribute("id") ?? href, {
      id: el.getAttribute("id") ?? href,
      path: resolvePath(opfPath, href).path,
      type: el.getAttribute("media-type") ?? "",
      properties: el.getAttribute("properties") ?? "",
    });
  }

  const spineEl = opf.getElementsByTagNameNS("*", "spine")[0];
  const spine = Array.from(spineEl?.getElementsByTagNameNS("*", "itemref") ?? [])
    .map((ref) => manifest.get(ref.getAttribute("idref") ?? ""))
    .filter((item): item is ManifestItem => Boolean(item));
  const chapterIndex = new Map(spine.map((item, i) => [item.path, i]));

  const objectUrls = new Map<string, string>();
  const resourceUrl = async (path: string) => {
    let url = objectUrls.get(path);
    if (!url) {
      const file = zip.file(path);
      if (!file) return "";
      const item = [...manifest.values()].find((m) => m.path === path);
      url = URL.createObjectURL(new Blob([await file.async("arraybuffer")], { type: item?.type }));
      objectUrls.set(path, url);
    }
    return url;
  };

  const chapterCache = new Map<number, Promise<DocumentFragment>>();
  const parseChapter = async (index: number) => {
    const { path } = spine[index];
    const doc = parseXml(await readText(path), "application/xhtml+xml");
    const body = doc.body ?? doc.getElementsByTagName("body")[0] ?? doc.documentElement;
    sanitize(body);

    await Promise.all(
      Array.from(body.querySelectorAll("img[src], image")).map(async (el) => {
        const attr = el.hasAttribute("src") ? "src" : el.hasAttribute("href") ? "href" : "xlink:href";
        const src = el.getAttribute(attr) ?? el.getAttributeNS("http://www.w3.org/1999/xlink", "href");
        if (!src || isExternal(src)) return;
        const url = await resourceUrl(resolvePath(path, src).path);
        el.setAttribute(el.localName === "image" ? "href" : "src", url);
      }),
    );

    body.querySelectorAll("a[href]").forEach((a) => {
      const href = a.getAttribute("href")!;
      if (isExternal(href)) {
        a.setAttribute("data-external", href);
      } else {
        const { path: target, hash } = resolvePath(path, href);
        a.setAttribute("data-href", hash ? `${target}#${hash}` : target);
      }
      a.removeAttribute("href");
    });

    return toFragment(body);
  };

  const toc = await readToc(opf, manifest, readText, chapterIndex);

  return {
    layout: "reflow",
    metadata: { title: textOf(opf, "title"), author: textOf(opf, "creator"), language: textOf(opf, "language") },
    toc,
    chapterCount: spine.length,

    async loadChapter(index) {
      if (!chapterCache.has(index)) chapterCache.set(index, parseChapter(index));
      return (await chapterCache.get(index)!).cloneNode(true) as DocumentFragment;
    },

    resolveLink(href) {
      const [path, anchor] = href.split("#");
      const chapter = chapterIndex.get(path);
      return chapter === undefined ? null : { chapter, anchor };
    },

    async cover() {
      const items = [...manifest.values()];
      const coverId = opf.querySelector('meta[name="cover"]')?.getAttribute("content");
      const item =
        items.find((m) => m.properties.split(" ").includes("cover-image")) ??
        (coverId ? manifest.get(coverId) : undefined) ??
        items.find((m) => m.type.startsWith("image/") && /cover/i.test(m.id + m.path));
      const file = item && zip.file(item.path);
      return file ? new Blob([await file.async("arraybuffer")], { type: item.type }) : null;
    },

    destroy() {
      objectUrls.forEach((url) => URL.revokeObjectURL(url));
      objectUrls.clear();
    },
  };
}

async function readToc(
  opf: Document,
  manifest: Map<string, ManifestItem>,
  readText: (path: string) => Promise<string>,
  chapterIndex: Map<string, number>,
): Promise<TocEntry[]> {
  const entries: TocEntry[] = [];
  const add = (label: string, base: string, href: string, depth: number) => {
    const { path, hash } = resolvePath(base, href);
    const chapter = chapterIndex.get(path);
    if (label && chapter !== undefined) entries.push({ label, depth, chapter, anchor: hash });
  };

  const nav = [...manifest.values()].find((m) => m.properties.split(" ").includes("nav"));
  if (nav) {
    const doc = parseXml(await readText(nav.path), "application/xhtml+xml");
    const tocNav =
      Array.from(doc.getElementsByTagName("nav")).find((n) => /toc/.test(n.getAttribute("epub:type") ?? n.getAttributeNS("*", "type") ?? "")) ??
      doc.getElementsByTagName("nav")[0];
    const walk = (ol: Element | null, depth: number) => {
      for (const li of Array.from(ol?.children ?? []).filter((c) => c.localName === "li")) {
        const a = Array.from(li.children).find((c) => c.localName === "a" || c.localName === "span");
        if (a?.getAttribute("href")) add(a.textContent?.trim() ?? "", nav.path, a.getAttribute("href")!, depth);
        walk(Array.from(li.children).find((c) => c.localName === "ol") ?? null, depth + 1);
      }
    };
    walk(tocNav ? Array.from(tocNav.children).find((c) => c.localName === "ol") ?? null : null, 0);
    if (entries.length) return entries;
  }

  const ncxId = opf.getElementsByTagNameNS("*", "spine")[0]?.getAttribute("toc");
  const ncx = (ncxId && manifest.get(ncxId)) || [...manifest.values()].find((m) => m.type === "application/x-dtbncx+xml");
  if (ncx) {
    const doc = parseXml(await readText(ncx.path));
    const walk = (parent: Element, depth: number) => {
      for (const point of Array.from(parent.children).filter((c) => c.localName === "navPoint")) {
        const label = textOf(point.getElementsByTagNameNS("*", "navLabel")[0], "text");
        const src = point.getElementsByTagNameNS("*", "content")[0]?.getAttribute("src");
        if (src) add(label, ncx.path, src, depth);
        walk(point, depth + 1);
      }
    };
    const navMap = doc.getElementsByTagNameNS("*", "navMap")[0];
    if (navMap) walk(navMap, 0);
  }
  return entries;
}
