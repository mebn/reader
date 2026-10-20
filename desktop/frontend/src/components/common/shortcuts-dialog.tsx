import { useState } from "react";
import { useLocation } from "wouter";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { usePin } from "@/store/pin";
import { formatCombo, SHORTCUT_GROUPS, SHORTCUTS, useShortcuts } from "@/lib/shortcuts";

/** App-wide navigation shortcuts, and the list of every shortcut behind "?". */
export function GlobalShortcuts() {
  const [location, navigate] = useLocation();
  const [open, setOpen] = useState(false);
  const reading = location.startsWith("/read/") || location.startsWith("/window/");

  useShortcuts({
    help: () => setOpen((o) => !o),
    pin: () => void usePin.getState().toggle(),
    library: () => (reading ? false : navigate("/")),
    // The reader opens its own appearance settings instead.
    settings: () => (reading ? false : navigate("/settings")),
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
        <DialogTitle>Keyboard shortcuts</DialogTitle>
        <ShortcutList />
      </DialogContent>
    </Dialog>
  );
}

/** Every shortcut, grouped by where it works. */
export function ShortcutList() {
  return (
    <div className="grid gap-x-8 gap-y-6 sm:grid-cols-2">
      {SHORTCUT_GROUPS.map((group) => (
        <section key={group.title}>
          <h3 className="mb-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase">{group.title}</h3>
          <dl className="grid gap-1.5">
            {group.ids.map((id) => (
              <div key={id} className="flex items-center justify-between gap-4 text-sm">
                <dt>{id === "back" && group.title === "Library" ? "Up a folder" : SHORTCUTS[id].label}</dt>
                <dd className="flex shrink-0 gap-1">
                  {SHORTCUTS[id].keys.slice(0, 2).map((combo) => (
                    <kbd key={combo} className="rounded border bg-muted px-1.5 py-0.5 font-sans text-[11px] text-muted-foreground">
                      {formatCombo(combo)}
                    </kbd>
                  ))}
                </dd>
              </div>
            ))}
          </dl>
        </section>
      ))}
    </div>
  );
}
