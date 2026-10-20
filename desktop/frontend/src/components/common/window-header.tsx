import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

interface WindowHeaderProps {
  left?: ReactNode;
  center?: ReactNode;
  right?: ReactNode;
  className?: string;
}

/** A header that doubles as the draggable title bar. */
export function WindowHeader({ left, center, right, className }: WindowHeaderProps) {
  return (
    <header className={cn("drag-region traffic-light-inset relative z-20 flex h-(--titlebar-height) shrink-0 items-center gap-2 px-4", className)}>
      <div className="flex min-w-0 flex-1 items-center gap-1">{left}</div>
      {/* Hidden when narrow, where it would run into the left side. */}
      {center && <div className="pointer-events-none absolute inset-x-40 truncate text-center text-sm font-medium max-[640px]:hidden">{center}</div>}
      <div className="flex items-center gap-1">{right}</div>
    </header>
  );
}
