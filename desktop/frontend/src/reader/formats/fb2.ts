import { nameWithoutExtension, parseXml, textOf } from "./dom";
import type { ReflowDocument, TocEntry } from "./types";

const XLINK = "http://www.w3.org/1999/xlink";

/** FictionBook element → HTML tag. Unlisted elements become their children. */
const TAGS: Record<string, string> = {
  p: "p",
  title: "h2",
  subtitle: "h3",
  emphasis: "em",
  strong: "strong",
  strikethrough: "s",
  sup: "sup",
  sub: "sub",
  code: "code",
  epigraph: "blockquote",
  cite: "blockquote",
  poem: "div",
  stanza: "p",
  v: "div",
  "text-author": "p",
  section: "section",
  table: "table",
  tr: "tr",
  td: "td",
  th: "th",
};

export async function openFb2(data: Blob, fileName: string): Promise<ReflowDocument> {
  const doc = parseXml(await data.text());
  const info = doc.getElementsByTagNameNS("*", "title-info")[0];
  const author = info?.getElementsByTagNameNS("*", "author")[0];
  const title = textOf(info, "book-title") || nameWithoutExtension(fileName);

  const binaries = new Map<string, Blob>();
  for (const bin of Array.from(doc.getElementsByTagNameNS("*", "binary"))) {
    const bytes = Uint8Array.from(atob((bin.textContent ?? "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
    binaries.set(bin.getAttribute("id") ?? "", new Blob([bytes], { type: bin.getAttribute("content-type") ?? "image/jpeg" }));
  }
  const urls = new Map<string, string>();
  const imageUrl = (href: string | null) => {
    const id = href?.replace(/^#/, "") ?? "";
    if (!binaries.has(id)) return "";
    if (!urls.has(id)) urls.set(id, URL.createObjectURL(binaries.get(id)!));
    return urls.get(id)!;
  };

  const body = Array.from(doc.getElementsByTagNameNS("*", "body")).find((b) => b.getAttribute("name") !== "notes");
  const sections = Array.from(body?.children ?? []).filter((c) => c.localName === "section");
  const chapters = sections.length ? sections : body ? [body] : [];

  const anchors = new Map<string, number>();
  chapters.forEach((ch, i) => ch.querySelectorAll("[id]").forEach((el) => anchors.set(el.getAttribute("id")!, i)));

  const convert = (node: Node): Node | null => {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent ?? "");
    if (node.nodeType !== Node.ELEMENT_NODE) return null;
    const el = node as Element;
    const name = el.localName;

    if (name === "image") {
      const img = document.createElement("img");
      img.src = imageUrl(el.getAttributeNS(XLINK, "href") ?? el.getAttribute("l:href"));
      return img;
    }
    if (name === "empty-line") return document.createElement("br");
    if (name === "a") {
      const a = document.createElement("a");
      const href = el.getAttributeNS(XLINK, "href") ?? "";
      a.setAttribute(href.startsWith("#") ? "data-href" : "data-external", href.replace(/^#/, ""));
      el.childNodes.forEach((c) => a.append(convert(c) ?? ""));
      return a;
    }

    const out = TAGS[name] ? document.createElement(TAGS[name]) : document.createDocumentFragment();
    if (out instanceof Element && el.id) out.id = el.id;
    el.childNodes.forEach((c) => {
      const converted = convert(c);
      if (converted) out.appendChild(converted);
    });
    return out;
  };

  const toc: TocEntry[] = chapters.map((ch, i) => ({
    label: Array.from(ch.children).find((c) => c.localName === "title")?.textContent?.trim().replace(/\s+/g, " ") || `${i + 1}`,
    depth: 0,
    chapter: i,
  }));

  return {
    layout: "reflow",
    metadata: {
      title,
      author: [textOf(author, "first-name"), textOf(author, "last-name")].filter(Boolean).join(" "),
      language: textOf(info, "lang"),
    },
    toc,
    chapterCount: chapters.length,

    async loadChapter(index) {
      const fragment = document.createDocumentFragment();
      chapters[index].childNodes.forEach((c) => {
        const converted = convert(c);
        if (converted) fragment.appendChild(converted);
      });
      return fragment;
    },

    resolveLink(href) {
      const chapter = anchors.get(href);
      return chapter === undefined ? null : { chapter, anchor: href };
    },

    async cover() {
      const image = info?.getElementsByTagNameNS("*", "coverpage")[0]?.getElementsByTagNameNS("*", "image")[0];
      const id = (image?.getAttributeNS(XLINK, "href") ?? "").replace(/^#/, "");
      return binaries.get(id) ?? null;
    },

    destroy() {
      urls.forEach((url) => URL.revokeObjectURL(url));
    },
  };
}
