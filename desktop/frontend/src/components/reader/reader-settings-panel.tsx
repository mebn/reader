import { Type } from "lucide-react";
import { HeaderFooterSettings, LayoutSettings, PageSettings, TextSettings } from "@/components/settings/reader-settings-form";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { ReaderSettings } from "@/lib/settings";
import { FloatingPanel } from "./floating-panel";

interface ReaderSettingsPanelProps {
  open: boolean;
  value: ReaderSettings;
  /** Whether the app is dark right now. */
  dark: boolean;
  /** Switches the whole app, this page included, to light or dark. */
  onModeChange(mode: "light" | "dark"): void;
  /** Whether this book has settings of its own. */
  hasOverride: boolean;
  onOpenChange(open: boolean): void;
  onChange(patch: Partial<ReaderSettings>): void;
  onMakeDefault(): void;
  onReset(): void;
}

const TABS = [
  ["text", "Text"],
  ["page", "Page"],
  ["layout", "Layout"],
  ["header-footer", "Header & footer"],
] as const;

/**
 * Appearance of the open book, in tabs. Not modal and off to the side, so the page stays
 * in view and every change shows on it right away. Changes apply to this book; they can
 * be promoted to every book or dropped.
 */
export function ReaderSettingsPanel({ open, value, dark, onModeChange, hasOverride, onOpenChange, onChange, onMakeDefault, onReset }: ReaderSettingsPanelProps) {
  const section = { value, onChange, title: null };
  return (
    <FloatingPanel open={open} onOpenChange={onOpenChange} label="Appearance" shortcut="appearance" icon={<Type />}>
      <Tabs defaultValue="text" className="flex min-h-0 flex-1 flex-col gap-0">
        {/* Tabs take room by their labels, so the long one isn't squeezed. */}
        <TabsList className="m-3 mb-0 flex w-auto">
          {TABS.map(([id, label]) => (
            <TabsTrigger key={id} value={id} className="flex-auto px-3 text-xs">
              {label}
            </TabsTrigger>
          ))}
        </TabsList>
        <div className="min-h-0 flex-1 overflow-y-auto p-4">
          <TabsContent value="page">
            <PageSettings {...section} mode={dark ? "dark" : "light"} onModeChange={onModeChange} />
          </TabsContent>
          <TabsContent value="text">
            <TextSettings {...section} />
          </TabsContent>
          <TabsContent value="layout">
            <LayoutSettings {...section} />
          </TabsContent>
          <TabsContent value="header-footer">
            <HeaderFooterSettings {...section} />
          </TabsContent>
        </div>
      </Tabs>
      <div className="flex items-center gap-2 border-t p-3">
        {hasOverride ? (
          <>
            <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={onReset}>
              Use defaults
            </Button>
            <Button variant="outline" size="sm" className="ml-auto" onClick={onMakeDefault}>
              Use for all books
            </Button>
          </>
        ) : (
          <p className="px-1 py-1.5 text-xs text-muted-foreground">Changes apply to this book.</p>
        )}
      </div>
    </FloatingPanel>
  );
}
