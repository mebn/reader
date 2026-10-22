import { THEMED } from "./formats/dom";

/** What a book's CSS may not set on the text column itself, since the renderer pages it. */
const PAGED = /^(position|inset|top|right|bottom|left|width|height|(min|max)-(width|height)|margin.*|padding.*|columns?.*|overflow.*|transform|float|display)$/;
const ROOT = /(^|[\s>+~,(])(html|body)(?=$|[\s.#:[>+~,)])/gi;

/**
 * Turns a book's CSS into rules that only reach its text: everything is scoped to the
 * book content in original-styles mode, `html` and `body` become the text column, and
 * whatever would break paging or the reader's theme colors is dropped.
 */
export function scopeBookCss(css: string): string {
  const sheet = new CSSStyleSheet();
  try {
    sheet.replaceSync(css);
  } catch {
    return "";
  }
  const fonts: string[] = [];
  const scoped = (rules: CSSRuleList): string[] =>
    Array.from(rules).flatMap((rule) => {
      if (rule instanceof CSSFontFaceRule) {
        fonts.push(rule.cssText);
        return [];
      }
      if (rule instanceof CSSMediaRule) {
        const inner = scoped(rule.cssRules);
        return inner.length ? [`@media ${rule.conditionText} { ${wrap(inner)} }`] : [];
      }
      if (!(rule instanceof CSSStyleRule)) return [];
      const selector = rule.selectorText.replace(ROOT, "$1:scope");
      const style = rule.style;
      for (const property of Array.from(style)) {
        if (THEMED.test(property) || /url\(/i.test(style.getPropertyValue(property)) || style.getPropertyValue(property).includes("fixed")) {
          style.removeProperty(property);
        } else if (selector.includes(":scope") && PAGED.test(property)) {
          style.removeProperty(property);
        }
      }
      return style.length ? [`${selector} { ${style.cssText} }`] : [];
    });
  const rules = scoped(sheet.cssRules);
  return [...fonts, rules.length ? wrap(rules) : ""].join("\n");
}

function wrap(rules: string[]) {
  return `@scope (.book-content[data-original]) { ${rules.join("\n")} }`;
}
