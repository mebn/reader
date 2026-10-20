import { Fragment } from "react";
import { Link } from "wouter";
import type { Folder } from "@/lib/types";
import { cn } from "@/lib/utils";
import { moveItem, useDropTarget } from "./drag";

function Crumb({ folder, current }: { folder: Folder | null; current: boolean }) {
  const drop = useDropTarget((item) => moveItem(item, folder?.id ?? null));
  const label = folder?.name ?? "Library";
  const className = cn(
    "truncate rounded-md px-1.5 py-0.5 text-[15px] transition-colors",
    current ? "font-semibold" : "text-muted-foreground hover:text-foreground",
    drop.over && "bg-accent text-foreground",
  );

  if (current) return <span className={className}>{label}</span>;
  return (
    <Link href={folder ? `/folder/${folder.id}` : "/"} className={className} {...drop.props}>
      {label}
    </Link>
  );
}

/** Library › Folder › Subfolder. Crumbs accept dropped books and folders. */
export function Breadcrumbs({ path }: { path: Folder[] }) {
  const crumbs: (Folder | null)[] = [null, ...path];
  return (
    <nav className="flex min-w-0 items-center">
      {crumbs.map((folder, i) => (
        <Fragment key={folder?.id ?? "root"}>
          {i > 0 && <span className="px-0.5 text-muted-foreground/50">/</span>}
          <Crumb folder={folder} current={i === crumbs.length - 1} />
        </Fragment>
      ))}
    </nav>
  );
}
