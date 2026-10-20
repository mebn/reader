import { useRef, useState } from "react";
import { Plus } from "lucide-react";
import { NameDialog } from "@/components/common/name-dialog";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { createFolder, importFiles } from "@/lib/actions";
import { FORMATS } from "@/lib/types";

export function AddMenu({ folderId }: { folderId: string | null }) {
  const input = useRef<HTMLInputElement>(null);
  const [naming, setNaming] = useState(false);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label="Add">
            <Plus className="size-[18px]" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-36">
          <DropdownMenuItem onSelect={() => input.current?.click()}>Book</DropdownMenuItem>
          <DropdownMenuItem onSelect={() => setNaming(true)}>Folder</DropdownMenuItem>
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
