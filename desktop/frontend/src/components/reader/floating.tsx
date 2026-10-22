import { useEffect, useRef, type ReactNode } from "react";
import { Popover, PopoverAnchor, PopoverContent } from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import { swallowNextClick } from "./floating-panel";

interface FloatingProps {
  rect: DOMRect | null;
  children: ReactNode;
  className?: string;
  onClose(): void;
}

/** A popover anchored to an arbitrary rectangle on screen, such as a text selection. */
export function Floating({ rect, children, className, onClose }: FloatingProps) {
  const open = Boolean(rect);
  const content = useRef<HTMLDivElement>(null);
  const latestOnClose = useRef(onClose);
  latestOnClose.current = onClose;

  // A press outside only closes it: the toolbar button or link under it isn't clicked too.
  // Closed here rather than by Radix, which waits for the click and lets it through.
  useEffect(() => {
    if (!open) return;
    const press = (e: PointerEvent) => {
      if (content.current?.contains(e.target as Node)) return;
      latestOnClose.current();
      swallowNextClick();
    };
    document.addEventListener("pointerdown", press, true);
    return () => document.removeEventListener("pointerdown", press, true);
  }, [open]);

  return (
    <Popover open={open} onOpenChange={(open) => !open && onClose()}>
      <PopoverAnchor asChild>
        <div
          className="pointer-events-none fixed"
          style={rect ? { left: rect.left, top: rect.top, width: rect.width, height: rect.height } : { display: "none" }}
        />
      </PopoverAnchor>
      <PopoverContent
        ref={content}
        // The reader's own popover: its keyboard shortcuts keep working while it shows.
        data-floating-panel
        side="top"
        sideOffset={8}
        className={cn("w-auto p-1.5", className)}
        onOpenAutoFocus={(e) => e.preventDefault()}
        onCloseAutoFocus={(e) => e.preventDefault()}
      >
        {children}
      </PopoverContent>
    </Popover>
  );
}
