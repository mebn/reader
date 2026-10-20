import { Type } from "lucide-react";
import { ReaderSettingsForm } from "@/components/settings/reader-settings-form";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { ReaderSettings } from "@/lib/settings";
import { ChromeButton } from "./reader-toolbar";

interface ReaderSettingsPanelProps {
  open: boolean;
  value: ReaderSettings;
  dirty: boolean;
  hasOverride: boolean;
  onOpenChange(open: boolean): void;
  onChange(patch: Partial<ReaderSettings>): void;
  onSaveBook(): void;
  onSaveDefault(): void;
  onReset(): void;
}

/** Live-preview settings; changes stick once saved for this book or all books. */
export function ReaderSettingsPanel({ open, value, dirty, hasOverride, onOpenChange, onChange, onSaveBook, onSaveDefault, onReset }: ReaderSettingsPanelProps) {
  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>
        <ChromeButton active={open} aria-label="Appearance">
          <Type />
        </ChromeButton>
      </PopoverTrigger>
      <PopoverContent align="end" sideOffset={6} className="w-[340px] p-0">
        <div className="max-h-[min(600px,calc(100vh-140px))] overflow-y-auto p-4">
          <ReaderSettingsForm value={value} onChange={onChange} />
        </div>
        <div className="flex items-center gap-2 border-t p-3">
          {hasOverride && !dirty && (
            <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={onReset}>
              Use defaults
            </Button>
          )}
          <div className="ml-auto flex gap-2">
            <Button variant="outline" size="sm" disabled={!dirty} onClick={onSaveBook}>
              This book
            </Button>
            <Button size="sm" disabled={!dirty} onClick={onSaveDefault}>
              All books
            </Button>
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
}
