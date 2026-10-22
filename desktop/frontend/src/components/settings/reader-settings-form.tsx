import type { ReactNode } from "react";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { BACKGROUNDS, FONTS, type ReaderSettings } from "@/lib/settings";
import { cn } from "@/lib/utils";

interface SectionProps {
  value: ReaderSettings;
  onChange(patch: Partial<ReaderSettings>): void;
}

interface PageSectionProps extends SectionProps {
  /** Which mode's page color is being edited. */
  mode: "light" | "dark";
  onModeChange(mode: "light" | "dark"): void;
}

/** Every reader setting, one section after another. */
export function ReaderSettingsForm(props: PageSectionProps) {
  return (
    <div className="grid gap-8">
      <PageSettings {...props} />
      <TextSettings {...props} />
      <LayoutSettings {...props} />
      <HeaderFooterSettings {...props} />
    </div>
  );
}

export function PageSettings({ value, mode, onModeChange, onChange, title = "Page" }: PageSectionProps & { title?: string | null }) {
  const backgroundKey = mode === "dark" ? "darkBackground" : "lightBackground";
  return (
    <div className="grid gap-5">
      <SectionHeader label={title} />
      <Row label="Mode">
        <Segmented
          value={mode}
          options={[
            ["light", "Light"],
            ["dark", "Dark"],
          ]}
          onChange={(m) => onModeChange(m as "light" | "dark")}
        />
      </Row>
      <Row label="Background">
        <div className="flex flex-wrap justify-end gap-1.5">
          {BACKGROUNDS.map((bg) => (
            <Swatch key={bg.id} selected={value[backgroundKey] === bg.id} onClick={() => onChange({ [backgroundKey]: bg.id })} label={bg.id} style={{ background: bg.color }} />
          ))}
        </div>
      </Row>
    </div>
  );
}

export function TextSettings({ value, onChange, title = "Text" }: SectionProps & { title?: string | null }) {
  return (
    <div className="grid gap-5">
      <SectionHeader label={title} />
      <div className="-mt-2 grid grid-cols-3 gap-1.5">
        {FONTS.map((font) => (
          <button
            key={font.id}
            type="button"
            onClick={() => onChange({ font: font.id })}
            className={cn(
              "rounded-lg border px-2 py-2 text-left transition-colors hover:bg-accent",
              value.font === font.id ? "border-foreground/60 bg-accent" : "border-border",
            )}
          >
            <div className="text-lg leading-none" style={{ fontFamily: font.family }}>
              Aa
            </div>
            <div className="mt-1 truncate text-[11px] text-muted-foreground">{font.label}</div>
          </button>
        ))}
      </div>
      <Range label="Size" value={value.fontSize} min={12} max={34} step={1} format={(v) => `${v}`} onChange={(fontSize) => onChange({ fontSize })} />
      <Range label="Line height" value={value.lineHeight} min={1.1} max={2.4} step={0.05} format={(v) => v.toFixed(2)} onChange={(lineHeight) => onChange({ lineHeight })} />
      <Range label="Weight" value={value.weight} min={300} max={700} step={50} format={(v) => `${v}`} onChange={(weight) => onChange({ weight })} />
      <Range label="Spacing" value={value.tracking} min={-0.03} max={0.12} step={0.005} format={(v) => (v * 100).toFixed(1)} onChange={(tracking) => onChange({ tracking })} />
    </div>
  );
}

export function LayoutSettings({ value, onChange, title = "Layout" }: SectionProps & { title?: string | null }) {
  return (
    <div className="grid gap-5">
      <SectionHeader label={title} />
      <Range label="Margins" value={value.sideMargin} min={0} max={40} step={1} format={(v) => (v ? `${v}%` : "None")} onChange={(sideMargin) => onChange({ sideMargin })} />
      <Range label="Paragraphs" value={value.paragraphSpacing} min={0} max={2} step={0.1} format={(v) => v.toFixed(1)} onChange={(paragraphSpacing) => onChange({ paragraphSpacing })} />
      <Row label="Align">
        <Segmented
          value={value.align}
          options={[
            ["left", "Left"],
            ["justify", "Justify"],
          ]}
          onChange={(align) => onChange({ align: align as ReaderSettings["align"] })}
        />
      </Row>
      <PagesSetting value={value} onChange={onChange} />
      <Row label="Hyphenation">
        <Switch checked={value.hyphenate} onCheckedChange={(hyphenate) => onChange({ hyphenate })} />
      </Row>
      <Row label="Original styles">
        <Switch checked={value.originalStyles} onCheckedChange={(originalStyles) => onChange({ originalStyles })} />
      </Row>
    </div>
  );
}

/** One page at a time, or two side by side when the window is wide enough. */
export function PagesSetting({ value, onChange }: SectionProps) {
  return (
    <Row label="Pages">
      <Segmented
        value={String(value.pages)}
        options={[
          ["1", "One"],
          ["2", "Two"],
        ]}
        onChange={(pages) => onChange({ pages: Number(pages) as 1 | 2 })}
      />
    </Row>
  );
}

export function HeaderFooterSettings({ value, onChange, title = "Header & footer" }: SectionProps & { title?: string | null }) {
  return (
    <div className="grid gap-5">
      <SectionHeader label={title} />
      <div className="grid gap-3">
        <span className="text-[13px] text-muted-foreground">Header</span>
        <Toggle label="Book title" checked={value.headerTitle} onChange={(headerTitle) => onChange({ headerTitle })} />
        <Toggle label="Author" checked={value.headerAuthor} onChange={(headerAuthor) => onChange({ headerAuthor })} />
        <Toggle label="Chapter title" checked={value.headerChapter} onChange={(headerChapter) => onChange({ headerChapter })} />
        <Toggle label="Clock" checked={value.headerClock} onChange={(headerClock) => onChange({ headerClock })} />
      </div>
      <div className="grid gap-3">
        <span className="text-[13px] text-muted-foreground">Footer</span>
        <Toggle label="Chapter title" checked={value.footerChapter} onChange={(footerChapter) => onChange({ footerChapter })} />
        <Toggle label="Page in chapter" checked={value.footerChapterPages} onChange={(footerChapterPages) => onChange({ footerChapterPages })} />
        <Toggle label="Page in book" checked={value.footerBookPages} onChange={(footerBookPages) => onChange({ footerBookPages })} />
        <Toggle label="Percent read" checked={value.footerPercent} onChange={(footerPercent) => onChange({ footerPercent })} />
      </div>
    </div>
  );
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange(checked: boolean): void }) {
  return (
    <label className="flex items-center justify-between gap-4 pl-3">
      <span className="text-[13px]">{label}</span>
      <Switch checked={checked} onCheckedChange={onChange} />
    </label>
  );
}

/** A section's name; none in a tab, which already says it. */
function SectionHeader({ label }: { label: string | null }) {
  if (!label) return null;
  return (
    <div className="-mb-2 flex h-6 items-center">
      <span className="text-xs font-semibold tracking-wide text-foreground/80 uppercase">{label}</span>
    </div>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <span className="shrink-0 text-[13px] text-muted-foreground">{label}</span>
      {children}
    </div>
  );
}

function Segmented({ value, options, onChange }: { value: string; options: [string, string][]; onChange(v: string): void }) {
  return (
    <ToggleGroup type="single" variant="outline" size="sm" value={value} onValueChange={(v) => v && onChange(v)}>
      {options.map(([v, label]) => (
        <ToggleGroupItem key={v} value={v} className="px-3 text-xs">
          {label}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  );
}

function Swatch({ selected, label, style, onClick }: { selected: boolean; label: string; style: React.CSSProperties; onClick(): void }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      style={style}
      className={cn(
        "size-5 rounded-full ring-1 ring-black/10 transition-transform hover:scale-110 dark:ring-white/15",
        selected && "ring-2 ring-foreground ring-offset-2 ring-offset-background",
      )}
    />
  );
}

interface RangeProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format(v: number): string;
  onChange(v: number): void;
}

function Range({ label, value, min, max, step, format, onChange }: RangeProps) {
  return (
    <div className="grid grid-cols-[88px_1fr_36px] items-center gap-3">
      <span className="text-[13px] text-muted-foreground">{label}</span>
      <Slider value={[value]} min={min} max={max} step={step} onValueChange={([v]) => onChange(Number(v.toFixed(3)))} />
      <span className="text-right text-xs text-muted-foreground tabular-nums">{format(value)}</span>
    </div>
  );
}
