import { useEffect, useState, type ReactNode } from "react";
import { ChevronLeft } from "lucide-react";
import { Link } from "wouter";
import { Page } from "@/components/common/page";
import { WindowHeader } from "@/components/common/window-header";
import { ReaderSettingsForm } from "@/components/settings/reader-settings-form";
import { SettingsPreview } from "@/components/settings/settings-preview";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Switch } from "@/components/ui/switch";
import { saveSettings, useAppSettings, useDefaultReaderSettings } from "@/hooks/use-settings";
import { SCOPE, type ReaderSettings } from "@/lib/settings";
import { useSession } from "@/store/session";

export function SettingsPage() {
  const [app, setApp] = useAppSettings();
  const defaults = useDefaultReaderSettings();
  const session = useSession((s) => s.session);
  const signOut = useSession((s) => s.signOut);
  const [draft, setDraft] = useState<ReaderSettings>(defaults);

  // Picks up changes synced from other devices.
  useEffect(() => setDraft(defaults), [defaults]);

  // Saves shortly after the last change so dragging sliders doesn't flood sync.
  useEffect(() => {
    if (draft === defaults) return;
    const t = setTimeout(() => saveSettings(SCOPE.reader, draft), 400);
    return () => clearTimeout(t);
  }, [draft, defaults]);

  return (
    <Page variant="slide">
      <WindowHeader
        left={
          <Button variant="ghost" size="sm" asChild className="-ml-2 gap-1 text-muted-foreground">
            <Link href="/">
              <ChevronLeft className="size-4" />
              Library
            </Link>
          </Button>
        }
      />
      <ScrollArea className="min-h-0 flex-1">
        <div className="mx-auto grid max-w-4xl gap-10 px-8 pt-4 pb-16 md:grid-cols-[1fr_320px]">
          <div className="grid content-start gap-10">
            <Section title="Reading">
              <ReaderSettingsForm value={draft} onChange={(patch) => setDraft((d) => ({ ...d, ...patch }))} />
            </Section>

            <Section title="Books">
              <label className="flex items-center justify-between gap-4">
                <span className="text-[13px] text-muted-foreground">Open in new window</span>
                <Switch checked={app.openInNewWindow} onCheckedChange={(openInNewWindow) => setApp({ openInNewWindow })} />
              </label>
            </Section>

            <Section title="Account">
              <div className="flex items-center justify-between gap-4">
                <div className="min-w-0">
                  <div className="truncate text-sm">{session?.email}</div>
                  <div className="truncate text-xs text-muted-foreground">{session?.serverUrl}</div>
                </div>
                <Button variant="outline" size="sm" onClick={() => void signOut()}>
                  Sign out
                </Button>
              </div>
            </Section>
          </div>

          <div className="hidden md:block">
            <div className="sticky top-0">
              <SettingsPreview settings={draft} />
            </div>
          </div>
        </div>
      </ScrollArea>
    </Page>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-4 text-xs font-medium tracking-wide text-muted-foreground uppercase">{title}</h2>
      {children}
    </section>
  );
}
