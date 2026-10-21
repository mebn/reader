import { useEffect, useState } from "react";
import { Window } from "@wailsio/runtime";
import { Minus, Square, X } from "lucide-react";
import { cn } from "@/lib/utils";

/** Minimise, maximise and close, for Windows where the header stands in for the title bar. */
export function WindowControls() {
  const [maximised, setMaximised] = useState(false);

  useEffect(() => {
    const sync = () => void Window.IsMaximised().then(setMaximised);
    sync();
    window.addEventListener("resize", sync);
    return () => window.removeEventListener("resize", sync);
  }, []);

  return (
    <div className="window-controls fixed top-0 right-0 z-50 flex h-(--titlebar-height)">
      <CaptionButton label="Minimize" onClick={() => void Window.Minimise()}>
        <Minus />
      </CaptionButton>
      <CaptionButton label={maximised ? "Restore" : "Maximize"} onClick={() => void Window.ToggleMaximise()}>
        <Square className={cn("size-3", maximised && "size-2.5")} />
      </CaptionButton>
      <CaptionButton label="Close" danger onClick={() => void Window.Close()}>
        <X />
      </CaptionButton>
    </div>
  );
}

function CaptionButton({ label, danger, children, onClick }: { label: string; danger?: boolean; children: React.ReactNode; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className={cn(
        "grid w-[46px] place-items-center text-foreground/80 outline-none transition-colors [&_svg]:size-4 [&_svg]:stroke-[1.5]",
        danger ? "hover:bg-[#c42b1c] hover:text-white" : "hover:bg-foreground/10",
      )}
    >
      {children}
    </button>
  );
}
