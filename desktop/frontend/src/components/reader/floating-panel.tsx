import { useEffect, useRef, type ReactNode } from "react";
import { Hint } from "@/components/common/hint";
import { Dialog, DialogContent, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import type { ShortcutId } from "@/lib/shortcuts";
import { cn } from "@/lib/utils";
import { ChromeButton } from "./reader-toolbar";

interface FloatingPanelProps {
  open: boolean;
  onOpenChange(open: boolean): void;
  /** Names the panel and its toolbar button. */
  label: string;
  /** The hint on its button. */
  hint?: string;
  shortcut?: ShortcutId;
  icon: ReactNode;
  className?: string;
  children: ReactNode;
}

/** Drops the click that ends the current press, wherever it lands. */
function swallowNextClick() {
  const stop = (e: MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
  };
  window.addEventListener("click", stop, { capture: true, once: true });
  // A press that never becomes a click (a drag) mustn't leave the next real click dropped.
  window.addEventListener("pointerup", () => setTimeout(() => window.removeEventListener("click", stop, { capture: true }), 0), { once: true });
}

/**
 * A reader toolbar button and the panel it opens: floating under the toolbar on the
 * right, not modal, so the page stays in view and live. Anything inside can be used
 * without closing it; a press anywhere outside closes it and does nothing else.
 */
export function FloatingPanel({ open, onOpenChange, label, hint = label, shortcut, icon, className, children }: FloatingPanelProps) {
  const content = useRef<HTMLDivElement>(null);
  const latestOnOpenChange = useRef(onOpenChange);
  latestOnOpenChange.current = onOpenChange;

  // Closed here rather than by Radix, which waits for the click after the press and
  // stays open when the page has handled that click.
  useEffect(() => {
    if (!open) return;
    const press = (e: PointerEvent) => {
      const target = e.target as Element;
      if (content.current?.contains(target) || target.closest?.(`[data-panel-trigger="${label}"]`)) return;
      latestOnOpenChange.current(false);
      swallowNextClick();
    };
    document.addEventListener("pointerdown", press, true);
    return () => document.removeEventListener("pointerdown", press, true);
  }, [open, label]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange} modal={false}>
      <Hint label={hint} shortcut={shortcut}>
        <DialogTrigger asChild>
          <ChromeButton active={open} aria-label={label} data-panel-trigger={label}>
            {icon}
          </ChromeButton>
        </DialogTrigger>
      </Hint>
      <DialogContent
        ref={content}
        data-floating-panel
        showCloseButton={false}
        onOpenAutoFocus={(e) => e.preventDefault()}
        // Focus stays where it is, so the button's hint doesn't pop up on close.
        onCloseAutoFocus={(e) => e.preventDefault()}
        className={cn(
          "top-[calc(var(--titlebar-height)+4px)] right-4 left-auto flex max-h-[calc(100vh-var(--titlebar-height)-24px)] w-[400px] translate-x-0 translate-y-0 flex-col gap-0 overflow-hidden p-0 sm:max-w-[400px]",
          className,
        )}
      >
        <DialogTitle className="sr-only">{label}</DialogTitle>
        {children}
      </DialogContent>
    </Dialog>
  );
}
