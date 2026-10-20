import { nameWithoutExtension } from "./dom";
import type { ReflowDocument } from "./types";

const HEADING = /^\s*(chapter|kapitel|part|book|del)\s+([0-9]+|[ivxlcdm]+)\b.*$/i;
const MAX_CHAPTER_CHARS = 40_000;

interface TextChapter {
  title?: string;
  paragraphs: string[];
}

function decode(buffer: ArrayBuffer) {
  const utf8 = new TextDecoder("utf-8").decode(buffer);
  const broken = (utf8.match(/�/g) ?? []).length;
  return broken > utf8.length / 1000 ? new TextDecoder("windows-1252").decode(buffer) : utf8;
}

/** Splits plain text into chapters at headings, or into evenly sized parts. */
function split(text: string): TextChapter[] {
  const normalized = text.replace(/\r\n?/g, "\n");
  const blocks = /\n\s*\n/.test(normalized) ? normalized.split(/\n\s*\n+/) : normalized.split("\n");
  const paragraphs = blocks.map((p) => p.replace(/\s*\n\s*/g, " ").trim()).filter(Boolean);

  const chapters: TextChapter[] = [];
  let current: TextChapter = { paragraphs: [] };
  let size = 0;
  for (const p of paragraphs) {
    const heading = p.length < 80 && HEADING.test(p);
    if ((heading || size > MAX_CHAPTER_CHARS) && current.paragraphs.length) {
      chapters.push(current);
      current = { paragraphs: [] };
      size = 0;
    }
    if (heading) current.title = p;
    else current.paragraphs.push(p);
    size += p.length;
  }
  if (current.paragraphs.length || current.title) chapters.push(current);
  return chapters.length ? chapters : [{ paragraphs: [] }];
}

export async function openTxt(data: Blob, fileName: string): Promise<ReflowDocument> {
  const chapters = split(decode(await data.arrayBuffer()));

  return {
    layout: "reflow",
    metadata: { title: nameWithoutExtension(fileName), author: "" },
    toc: chapters.flatMap((c, i) => (c.title ? [{ label: c.title, depth: 0, chapter: i }] : [])),
    chapterCount: chapters.length,

    async loadChapter(index) {
      const fragment = document.createDocumentFragment();
      const { title, paragraphs } = chapters[index];
      if (title) fragment.appendChild(Object.assign(document.createElement("h2"), { textContent: title }));
      for (const text of paragraphs) fragment.appendChild(Object.assign(document.createElement("p"), { textContent: text }));
      return fragment;
    },
    resolveLink: () => null,
    cover: async () => null,
    destroy() {},
  };
}
