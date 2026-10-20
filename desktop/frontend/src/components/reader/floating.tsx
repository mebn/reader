import type { ReactNode } from "react";
import { Popover, PopoverAnchor, PopoverContent } from "@/components/ui/popover";
import { cn } from "@/lib/utils";

interface FloatingProps {
  rect: DOMRect | null;
  children: ReactNode;
  className?: string;
  onClose(): void;
}

/** A popover anchored to an arbitrary rectangle on screen, such as a text selection. */
export function Floating({ rect, children, className, onClose }: FloatingProps) {
  return (
    <Popover open={Boolean(rect)} onOpenChange={(open) => !open && onClose()}>
      <PopoverAnchor asChild>
        <div
          className="pointer-events-none fixed"
          style={rect ? { left: rect.left, top: rect.top, width: rect.width, height: rect.height } : { display: "none" }}
        />
      </PopoverAnchor>
      <PopoverContent
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
