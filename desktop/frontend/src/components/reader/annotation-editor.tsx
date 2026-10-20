import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { removeAnnotation, updateAnnotation } from "@/lib/actions";
import type { Annotation } from "@/lib/types";
import { ColorDots } from "./color-dots";

/** Edits a highlight's color and note. */
export function AnnotationEditor({ annotation, focusNote, onDone }: { annotation: Annotation; focusNote?: boolean; onDone(): void }) {
  const [note, setNote] = useState(annotation.note);
  useEffect(() => setNote(annotation.note), [annotation.id, annotation.note]);

  const saveNote = () => {
    if (note !== annotation.note) updateAnnotation(annotation, { note });
  };

  return (
    <div className="grid w-64 gap-2 p-1">
      <div className="flex items-center justify-between">
        <ColorDots value={annotation.color} onPick={(color) => updateAnnotation(annotation, { color })} />
        <Button
          variant="ghost"
          size="xs"
          className="text-muted-foreground hover:text-destructive"
          onClick={() => {
            removeAnnotation(annotation);
            onDone();
          }}
        >
          Remove
        </Button>
      </div>
      <textarea
        autoFocus={focusNote}
        value={note}
        placeholder="Note"
        rows={3}
        onChange={(e) => setNote(e.target.value)}
        onBlur={saveNote}
        onKeyDown={(e) => {
          e.stopPropagation();
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
            saveNote();
            onDone();
          }
        }}
        className="w-full resize-none rounded-md border bg-transparent px-2.5 py-2 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring/40"
      />
    </div>
  );
}
