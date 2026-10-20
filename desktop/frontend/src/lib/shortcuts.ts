import { useEffect, useRef } from "react";

/**
 * Key combos are written like "mod+shift+n": "mod" is ⌘ on macOS and Ctrl elsewhere,
 * the last part is a KeyboardEvent.key in lower case.
 */
export type Combo = string;

export const SHORTCUTS = {
  help: { keys: ["?"], label: "Keyboard shortcuts" },

  library: { keys: ["mod+1"], label: "Library" },
  settings: { keys: ["mod+,"], label: "Settings" },
  addBooks: { keys: ["mod+n"], label: "Add books" },
  newFolder: { keys: ["mod+shift+n"], label: "New folder" },
  search: { keys: ["mod+f"], label: "Search" },
  back: { keys: ["escape"], label: "Back" },

  next: { keys: ["arrowright", " ", "pagedown"], label: "Next page" },
  prev: { keys: ["arrowleft", "shift+ ", "pageup"], label: "Previous page" },
  bookmark: { keys: ["b", "mod+d"], label: "Bookmark this page" },
  contents: { keys: ["c"], label: "Contents, notes and bookmarks" },
  appearance: { keys: ["a"], label: "Appearance" },
  biggerText: { keys: ["mod+="], label: "Larger text" },
  smallerText: { keys: ["mod+-"], label: "Smaller text" },
  resetText: { keys: ["mod+0"], label: "Default text size" },
  pin: { keys: ["p"], label: "Keep window on top" },
  highlight: { keys: ["h"], label: "Highlight selection" },
  note: { keys: ["n"], label: "Highlight selection with a note" },
  close: { keys: ["escape"], label: "Close book" },
} as const satisfies Record<string, { keys: readonly Combo[]; label: string }>;

export type ShortcutId = keyof typeof SHORTCUTS;

export const SHORTCUT_GROUPS: { title: string; ids: ShortcutId[] }[] = [
  { title: "Everywhere", ids: ["library", "settings", "pin", "help"] },
  { title: "Library", ids: ["search", "addBooks", "newFolder", "back"] },
  { title: "Reading", ids: ["next", "prev", "bookmark", "contents", "appearance", "biggerText", "smallerText", "resetText", "close"] },
  { title: "With text selected", ids: ["highlight", "note"] },
];

const isMac = typeof navigator !== "undefined" && /mac/i.test(navigator.platform);

export function matches(e: KeyboardEvent, id: ShortcutId) {
  return SHORTCUTS[id].keys.some((combo) => matchesCombo(e, combo));
}

function matchesCombo(e: KeyboardEvent, combo: Combo) {
  const parts = combo === "shift+ " ? ["shift", " "] : combo.split("+").map((p) => p || "+");
  const key = parts.pop()!;
  const mod = parts.includes("mod");
  const shift = parts.includes("shift");
  if ((isMac ? e.metaKey : e.ctrlKey) !== mod || e.altKey) return false;
  if (isMac && e.ctrlKey) return false;
  // "?" needs Shift on most layouts, so Shift only counts for letters, space and named keys.
  if (key.length > 1 || /^[a-z ]$/.test(key)) {
    if (e.shiftKey !== shift) return false;
  }
  return e.key.toLowerCase() === key;
}

/** How a combo is shown to people, such as ⌘⇧N or Ctrl+Shift+N. */
export function formatCombo(combo: Combo) {
  const parts = combo === "shift+ " ? ["shift", " "] : combo.split("+").map((p) => p || "+");
  const names: Record<string, string> = isMac
    ? { mod: "⌘", shift: "⇧", arrowright: "→", arrowleft: "←", " ": "Space", pageup: "Page Up", pagedown: "Page Down", escape: "Esc" }
    : { mod: "Ctrl", shift: "Shift", arrowright: "→", arrowleft: "←", " ": "Space", pageup: "Page Up", pagedown: "Page Down", escape: "Esc" };
  const shown = parts.map((p) => names[p] ?? p.toUpperCase());
  return isMac ? shown.join(shown.length > 1 && shown.at(-1)!.length > 1 ? " " : "") : shown.join("+");
}

/** Whether a dialog, menu or popover is showing; those handle their own keys. */
function overlayOpen() {
  return Boolean(document.querySelector('[role="dialog"][data-state="open"], [role="alertdialog"][data-state="open"], [role="menu"][data-state="open"]'));
}

/** Whether a key press is meant for a text field rather than the app. */
export function typing(e: Event) {
  const el = e.target as HTMLElement | null;
  return Boolean(el?.closest("input, textarea, [contenteditable=true]"));
}

/**
 * Calls handlers for the shortcuts they're keyed by. The handler map can change on
 * every render; the listener stays put. A handler returning false lets the key through.
 */
export function useShortcuts(
  handlers: Partial<Record<ShortcutId, (e: KeyboardEvent) => boolean | void>>,
  options: { capture?: boolean; enabled?: boolean; /** Keep working while a dialog or menu is open. */ overOverlays?: boolean } = {},
) {
  const latest = useRef(handlers);
  latest.current = handlers;
  const { capture = false, enabled = true, overOverlays = false } = options;

  useEffect(() => {
    if (!enabled) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.isComposing) return;
      if (!overOverlays && overlayOpen()) return;
      for (const [id, handler] of Object.entries(latest.current) as [ShortcutId, (e: KeyboardEvent) => boolean | void][]) {
        if (!handler || !matches(e, id)) continue;
        // Plain keys belong to text fields; ⌘ combos and Escape still work while typing.
        if (typing(e) && !SHORTCUTS[id].keys.some((k) => k.startsWith("mod+") || k === "escape")) continue;
        if (handler(e) === false) continue;
        e.preventDefault();
        e.stopPropagation();
        return;
      }
    };
    window.addEventListener("keydown", onKey, capture);
    return () => window.removeEventListener("keydown", onKey, capture);
  }, [capture, enabled]);
}
