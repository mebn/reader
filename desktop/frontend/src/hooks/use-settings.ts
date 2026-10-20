import { useMemo } from "react";
import { sync } from "@/lib/sync";
import {
  DEFAULT_APP,
  DEFAULT_READER,
  parseSettings,
  SCOPE,
  type AppSettings,
  type ReaderSettings,
} from "@/lib/settings";
import { useLibrary } from "@/store/library";

function useScope(scope: string) {
  return useLibrary((s) => s.settings[scope]?.data);
}

export function saveSettings(scope: string, data: object | null) {
  const existing = useLibrary.getState().settings[scope];
  sync.put("settings", {
    id: scope,
    modifiedAt: existing?.modifiedAt ?? 0,
    data: data ? JSON.stringify(data) : "",
    deleted: data === null,
  });
}

export function useAppSettings(): [AppSettings, (patch: Partial<AppSettings>) => void] {
  const raw = useScope(SCOPE.app);
  const settings = useMemo(() => ({ ...DEFAULT_APP, ...parseSettings(raw, DEFAULT_APP) }), [raw]);
  return [settings, (patch) => saveSettings(SCOPE.app, { ...settings, ...patch })];
}

/** Reader defaults for every book. */
export function useDefaultReaderSettings(): ReaderSettings {
  const raw = useScope(SCOPE.reader);
  return useMemo(() => ({ ...DEFAULT_READER, ...parseSettings(raw, DEFAULT_READER) }), [raw]);
}

/** Effective settings for a book: defaults, then the book's own overrides. */
export function useBookReaderSettings(bookId: string) {
  const defaults = useDefaultReaderSettings();
  const raw = useScope(SCOPE.book(bookId));
  return useMemo(() => {
    const override = parseSettings(raw, DEFAULT_READER);
    return { settings: { ...defaults, ...override }, hasOverride: Object.keys(override).length > 0 };
  }, [defaults, raw]);
}
