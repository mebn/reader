import { useRef, useState } from "react";
import { Plus } from "lucide-react";
import { Hint } from "@/components/common/hint";
import { NameDialog } from "@/components/common/name-dialog";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuShortcut, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { createFolder, importFiles } from "@/lib/actions";
import { formatCombo, SHORTCUTS, useShortcuts } from "@/lib/shortcuts";
import { FORMATS } from "@/lib/types";

export function AddMenu({ folderId }: { folderId: string | null }) {
  const input = useRef<HTMLInputElement>(null);
  const [naming, setNaming] = useState(false);
  const [open, setOpen] = useState(false);

  useShortcuts({
    addBooks: () => input.current?.click(),
    newFolder: () => setNaming(true),
  });

  return (
    <>
      <DropdownMenu open={open} onOpenChange={setOpen}>
        <Hint label="Add books" shortcut="addBooks">
          <DropdownMenuTrigger asChild>
            {/* Opens on click rather than on press, so dragging the window from it doesn't open it. */}
            <Button variant="ghost" size="icon-sm" aria-label="Add" onPointerDown={(e) => e.preventDefault()} onClick={() => setOpen((o) => !o)}>
              <Plus className="size-[18px]" />
            </Button>
          </DropdownMenuTrigger>
        </Hint>
        <DropdownMenuContent align="end" className="w-36">
          <DropdownMenuItem onSelect={() => input.current?.click()}>
            Book
            <DropdownMenuShortcut>{formatCombo(SHORTCUTS.addBooks.keys[0])}</DropdownMenuShortcut>
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => setNaming(true)}>
            Folder
            <DropdownMenuShortcut>{formatCombo(SHORTCUTS.newFolder.keys[0])}</DropdownMenuShortcut>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <input
        ref={input}
        type="file"
        multiple
        hidden
        accept={FORMATS.map((f) => `.${f}`).join(",")}
        onChange={(e) => {
          void importFiles(Array.from(e.target.files ?? []), folderId);
          e.target.value = "";
        }}
      />
      <NameDialog open={naming} onOpenChange={setNaming} title="New folder" action="Create" onSubmit={(name) => createFolder(name, folderId)} />
    </>
  );
}
