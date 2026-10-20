import type { ReactNode } from "react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { formatCombo, SHORTCUTS, type ShortcutId } from "@/lib/shortcuts";

/** A label shown while hovering a control, with its keyboard shortcut when it has one. */
export function Hint({ label, shortcut, side = "bottom", children }: { label: string; shortcut?: ShortcutId; side?: "top" | "bottom" | "left" | "right"; children: ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger
        asChild
        // Only hovering shows it. Focus moves to these buttons on its own, such as when a
        // dialog opened with a shortcut closes again, and shouldn't pop it up.
        onFocus={(e) => e.preventDefault()}
      >
        {children}
      </TooltipTrigger>
      <TooltipContent side={side} className="flex items-center gap-2">
        {label}
        {shortcut && <kbd className="rounded bg-background/20 px-1 font-sans text-[10px] opacity-80">{formatCombo(SHORTCUTS[shortcut].keys[0])}</kbd>}
      </TooltipContent>
    </Tooltip>
  );
}
