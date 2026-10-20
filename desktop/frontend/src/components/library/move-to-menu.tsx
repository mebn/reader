import { useMemo } from "react";
import { ContextMenuItem, ContextMenuSub, ContextMenuSubContent, ContextMenuSubTrigger } from "@/components/ui/context-menu";
import type { Folder } from "@/lib/types";
import { useLibrary } from "@/store/library";

const byName = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

/** Folders as an indented tree, skipping `exclude` and its descendants. */
function useFolderTree(exclude?: string) {
  const folders = useLibrary((s) => s.folders);
  return useMemo(() => {
    const out: { folder: Folder; depth: number }[] = [];
    const walk = (parentId: string | null, depth: number) => {
      Object.values(folders)
        .filter((f) => (f.parentId ?? null) === parentId && f.id !== exclude)
        .sort((a, b) => byName.compare(a.name, b.name))
        .forEach((folder) => {
          out.push({ folder, depth });
          walk(folder.id, depth + 1);
        });
    };
    walk(null, 0);
    return out;
  }, [folders, exclude]);
}

interface MoveToMenuProps {
  current: string | null;
  exclude?: string;
  onMove(folderId: string | null): void;
}

export function MoveToMenu({ current, exclude, onMove }: MoveToMenuProps) {
  const tree = useFolderTree(exclude);
  return (
    <ContextMenuSub>
      <ContextMenuSubTrigger>Move to</ContextMenuSubTrigger>
      <ContextMenuSubContent className="max-h-80 min-w-44 overflow-y-auto">
        <ContextMenuItem disabled={current === null} onSelect={() => onMove(null)}>
          Library
        </ContextMenuItem>
        {tree.map(({ folder, depth }) => (
          <ContextMenuItem key={folder.id} disabled={folder.id === current} onSelect={() => onMove(folder.id)} style={{ paddingLeft: 8 + (depth + 1) * 12 }}>
            {folder.name}
          </ContextMenuItem>
        ))}
      </ContextMenuSubContent>
    </ContextMenuSub>
  );
}
