import { HIGHLIGHT_COLORS } from "@/reader/text-ranges";
import { cn } from "@/lib/utils";

export function ColorDots({ value, onPick }: { value?: string; onPick(color: string): void }) {
  return (
    <div className="flex items-center gap-1">
      {Object.entries(HIGHLIGHT_COLORS).map(([name, color]) => (
        <button
          key={name}
          type="button"
          aria-label={name}
          onClick={() => onPick(name)}
          className={cn("size-6 rounded-full transition-transform hover:scale-110", value === name && "ring-2 ring-foreground/70 ring-offset-2 ring-offset-popover")}
          style={{ background: color }}
        />
      ))}
    </div>
  );
}
