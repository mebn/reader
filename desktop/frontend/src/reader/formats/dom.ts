/** Helpers shared by the parsers that turn book markup into safe, plain HTML. */

const REMOVE = "script, style, link, meta, iframe, object, embed, form, input, button, textarea, select, noscript, audio, video";

export function parseXml(text: string, type: DOMParserSupportedType = "application/xml") {
  const doc = new DOMParser().parseFromString(text, type);
  if (type !== "text/html" && doc.getElementsByTagName("parsererror").length) {
    return new DOMParser().parseFromString(text, "text/html");
  }
  return doc;
}

/** Removes active content, inline styling and event handlers. */
export function sanitize(root: Element | DocumentFragment) {
  root.querySelectorAll(REMOVE).forEach((el) => el.remove());
  root.querySelectorAll("*").forEach((el) => {
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on") || name === "style" || name === "class" || name === "align" || name === "width" || name === "height") {
        el.removeAttribute(attr.name);
      }
    }
  });
}

export function toFragment(source: Element): DocumentFragment {
  const fragment = document.createDocumentFragment();
  const imported = document.importNode(source, true);
  while (imported.firstChild) fragment.appendChild(imported.firstChild);
  return fragment;
}

export function textOf(parent: Element | Document | null | undefined, localName: string) {
  return parent?.getElementsByTagNameNS("*", localName)[0]?.textContent?.trim() ?? "";
}

/** Resolves `href` against the directory of `from`, both zip-relative paths. */
export function resolvePath(from: string, href: string) {
  const [path, hash] = href.split("#");
  if (!path) return { path: from, hash };
  const parts = from.split("/").slice(0, -1);
  for (const segment of decodeURIComponent(path).split("/")) {
    if (segment === "..") parts.pop();
    else if (segment && segment !== ".") parts.push(segment);
  }
  return { path: parts.join("/"), hash };
}

export function isExternal(href: string) {
  return /^[a-z][a-z0-9+.-]*:/i.test(href);
}

export function nameWithoutExtension(fileName: string) {
  return fileName.replace(/\.[^.]+$/, "").replace(/[_]+/g, " ").trim();
}
