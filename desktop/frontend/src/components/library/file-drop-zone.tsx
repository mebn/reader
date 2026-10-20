import { useEffect, useRef, useState, type ReactNode } from "react";
import { importFiles } from "@/lib/actions";
import { cn } from "@/lib/utils";
import { platform } from "@/platform";

/** Accepts books dragged in from the OS and shows a soft overlay while hovering. */
export function FileDropZone({ folderId, children }: { folderId: string | null; children: ReactNode }) {
  const folderRef = useRef(folderId);
  folderRef.current = folderId;
  const [hovering, setHovering] = useState(false);

  useEffect(() => platform().onFilesDropped((files) => void importFiles(files, folderRef.current)), []);

  // In a plain browser there is no native drop class, so track file drags ourselves.
  useEffect(() => {
    let depth = 0;
    const isFiles = (e: DragEvent) => e.dataTransfer?.types.includes("Files");
    const enter = (e: DragEvent) => {
      if (!isFiles(e)) return;
      depth++;
      setHovering(true);
    };
    const leave = (e: DragEvent) => {
      if (isFiles(e) && --depth <= 0) setHovering(false);
    };
    const reset = () => {
      depth = 0;
      setHovering(false);
    };
    window.addEventListener("dragenter", enter);
    window.addEventListener("dragleave", leave);
    window.addEventListener("drop", reset);
    return () => {
      window.removeEventListener("dragenter", enter);
      window.removeEventListener("dragleave", leave);
      window.removeEventListener("drop", reset);
    };
  }, []);

  return (
    <div data-file-drop-target className="relative flex min-h-0 flex-1 flex-col">
      {children}
      <div
        className={cn(
          "drop-overlay pointer-events-none absolute inset-3 z-30 flex items-center justify-center rounded-2xl border-2 border-dashed border-foreground/20 bg-background/80 opacity-0 backdrop-blur-sm transition-opacity duration-200",
          hovering && "opacity-100",
        )}
      >
        <span className="text-sm text-muted-foreground">Drop to add</span>
      </div>
    </div>
  );
}
