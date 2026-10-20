import { useCallback, useEffect, useState, type ReactNode } from "react";
import { BookOpen, ChevronLeft, Globe, Keyboard, Laptop, Monitor, Moon, Palette, Smartphone, Sun, UserRound } from "lucide-react";
import { toast } from "sonner";
import { Link, useLocation } from "wouter";
import { ConfirmDialog } from "@/components/common/confirm-dialog";
import { Hint } from "@/components/common/hint";
import { Page } from "@/components/common/page";
import { ShortcutList } from "@/components/common/shortcuts-dialog";
import { formatWhen } from "@/components/library/book-details";
import { WindowHeader } from "@/components/common/window-header";
import { ReaderSettingsForm } from "@/components/settings/reader-settings-form";
import { SettingsPreview } from "@/components/settings/settings-preview";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Switch } from "@/components/ui/switch";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { saveSettings, useAppSettings, useDefaultReaderSettings } from "@/hooks/use-settings";
import { useIsDark } from "@/hooks/use-theme";
import { api } from "@/lib/api";
import { LIBRARY_TABS, SCOPE, type LibraryTab, type ReaderSettings, type ThemeMode } from "@/lib/settings";
import { useShortcuts } from "@/lib/shortcuts";
import type { Device } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useLibraryFilter } from "@/store/library-filter";
import { useSession } from "@/store/session";

type Pane = "appearance" | "reading" | "shortcuts" | "account";

const PANES: { id: Pane; label: string; icon: typeof Sun }[] = [
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "reading", label: "Reading", icon: BookOpen },
  { id: "shortcuts", label: "Shortcuts", icon: Keyboard },
  { id: "account", label: "Account", icon: UserRound },
];

export function SettingsPage() {
  const [pane, setPane] = useState<Pane>("appearance");
  const [, navigate] = useLocation();
  useShortcuts({ back: () => navigate("/") });

  return (
    <Page variant="zoom">
      <WindowHeader
        left={
          <Hint label="Back to the library" shortcut="library">
            <Button variant="ghost" size="sm" asChild className="-ml-2 gap-1 text-muted-foreground">
              <Link href="/">
                <ChevronLeft className="size-4" />
                Library
              </Link>
            </Button>
          </Hint>
        }
        center="Settings"
      />
      <div className="flex min-h-0 flex-1">
        <nav className="w-48 shrink-0 space-y-0.5 px-3 pt-2">
          {PANES.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              onClick={() => setPane(id)}
              className={cn(
                "flex w-full items-center gap-2.5 rounded-md px-2.5 py-1.5 text-left text-sm transition-colors",
                pane === id ? "bg-accent font-medium text-foreground" : "text-muted-foreground hover:bg-accent/60 hover:text-foreground",
              )}
            >
              <Icon className="size-4" />
              {label}
            </button>
          ))}
        </nav>
        <div className="min-w-0 flex-1 border-l">{pane === "appearance" ? <AppearancePane /> : pane === "reading" ? <ReadingPane /> : pane === "shortcuts" ? <ShortcutsPane /> : <AccountPane />}</div>
      </div>
    </Page>
  );
}

const THEMES: { id: ThemeMode; label: string; icon: typeof Sun }[] = [
  { id: "system", label: "System", icon: Monitor },
  { id: "light", label: "Light", icon: Sun },
  { id: "dark", label: "Dark", icon: Moon },
];

/** Light, dark or following the system, for the whole app. Applies as soon as it's picked. */
function AppearancePane() {
  const [app, setApp] = useAppSettings();

  return (
    <ScrollArea className="h-full">
      <div className="grid max-w-xl gap-10 px-8 pt-4 pb-16">
        <Section title="Theme">
          <div className="grid grid-cols-3 gap-3">
            {THEMES.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setApp({ theme: id })}
                className={cn(
                  "group rounded-xl border p-2 text-left transition-colors hover:bg-accent/50",
                  app.theme === id ? "border-foreground/50 ring-1 ring-foreground/20" : "border-border",
                )}
              >
                <ThemeSwatch mode={id} />
                <div className="mt-2 flex items-center gap-1.5 px-1 text-[13px]">
                  <Icon className="size-3.5 text-muted-foreground" />
                  {label}
                </div>
              </button>
            ))}
          </div>
          <p className="mt-3 text-xs text-muted-foreground">Books use the page colors you choose for light and dark under Reading.</p>
        </Section>

        <Section title="Library">
          <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
            <span className="text-[13px] text-muted-foreground">Start on</span>
            <ToggleGroup
              type="single"
              variant="outline"
              size="sm"
              value={app.defaultTab}
              onValueChange={(v) => {
                if (!v) return;
                setApp({ defaultTab: v as LibraryTab });
                // Show it on the way back to the library, not only after a restart.
                useLibraryFilter.getState().setTab(v as LibraryTab);
              }}
            >
              {LIBRARY_TABS.map(([value, label]) => (
                <ToggleGroupItem key={value} value={value} className="px-2.5 text-xs">
                  {label}
                </ToggleGroupItem>
              ))}
            </ToggleGroup>
          </div>
        </Section>
      </div>
    </ScrollArea>
  );
}

/** A miniature window in the theme's colors; System is split down the middle. */
function ThemeSwatch({ mode }: { mode: ThemeMode }) {
  const light = { bg: "#fbfaf7", bar: "#ebe8e2", line: "#d9d5ce" };
  const dark = { bg: "#1c1c1e", bar: "#2a2a2d", line: "#3a3a3e" };
  const half = (c: typeof light) => (
    <div className="flex-1 p-1.5" style={{ background: c.bg }}>
      <div className="mb-1.5 h-1.5 rounded-sm" style={{ background: c.bar }} />
      <div className="space-y-1">
        {[0.9, 0.7, 0.8].map((w) => (
          <div key={w} className="h-1 rounded-sm" style={{ background: c.line, width: `${w * 100}%` }} />
        ))}
      </div>
    </div>
  );
  return (
    <div className="flex aspect-[4/3] overflow-hidden rounded-md ring-1 ring-black/10 dark:ring-white/10">
      {mode !== "dark" && half(light)}
      {mode !== "light" && half(dark)}
    </div>
  );
}

/** Reader defaults for every book, plus library and account options. */
function ReadingPane() {
  const [app, setApp] = useAppSettings();
  const defaults = useDefaultReaderSettings();
  const [draft, setDraft] = useState<ReaderSettings>(defaults);
  const current = useIsDark(app.theme) ? "dark" : "light";
  const [mode, setMode] = useState<"light" | "dark">(current);

  // Picks up changes synced from other devices.
  useEffect(() => setDraft(defaults), [defaults]);

  // Saves shortly after the last change so dragging sliders doesn't flood sync.
  useEffect(() => {
    if (draft === defaults) return;
    const t = setTimeout(() => saveSettings(SCOPE.reader, draft), 400);
    return () => clearTimeout(t);
  }, [draft, defaults]);

  return (
    // The preview sits right beside the form rather than at the far edge of wide windows.
    <div className="grid h-full md:grid-cols-[minmax(0,36rem)_320px]">
      <ScrollArea className="min-h-0">
        <div className="grid content-start gap-10 px-8 pt-4 pb-16">
          <Section title="Reading">
            <ReaderSettingsForm
              value={draft}
              mode={mode}
              onModeChange={setMode}
              onChange={(patch) => setDraft((d) => ({ ...d, ...patch }))}
            />
          </Section>

          <Section title="Library">
            <label className="flex items-center justify-between gap-4">
              <span className="text-[13px] text-muted-foreground">Open books in a new window</span>
              <Switch checked={app.openInNewWindow} onCheckedChange={(openInNewWindow) => setApp({ openInNewWindow })} />
            </label>
          </Section>

        </div>
      </ScrollArea>

      {/* Outside the scroll area, so the preview stays whole while the form scrolls. */}
      <div className="hidden pt-4 pr-8 pb-8 pl-5 md:block">
        <SettingsPreview settings={draft} dark={mode === "dark"} />
      </div>
    </div>
  );
}

/** Every keyboard shortcut; the same list "?" shows anywhere in the app. */
function ShortcutsPane() {
  return (
    <ScrollArea className="h-full">
      <div className="max-w-3xl px-8 pt-4 pb-16">
        <Section title="Keyboard shortcuts">
          <ShortcutList />
        </Section>
        <p className="mt-8 text-xs text-muted-foreground">Press ? anywhere to see these.</p>
      </div>
    </ScrollArea>
  );
}

/** Who is signed in, and signing out. */
function AccountPane() {
  const session = useSession((s) => s.session);
  const signOut = useSession((s) => s.signOut);

  return (
    <ScrollArea className="h-full">
      <div className="grid max-w-xl gap-10 px-8 pt-4 pb-16">
        <Section title="Account">
          <div className="flex items-center justify-between gap-4">
            <div className="min-w-0">
              <div className="text-[13px] text-muted-foreground">Signed in as</div>
              <div className="truncate text-sm">{session?.email}</div>
            </div>
            <Button variant="outline" size="sm" onClick={() => void signOut()}>
              Sign out
            </Button>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">Your library, reading positions, highlights and settings stay in sync on every device you sign in on.</p>
        </Section>

        <Section title="Devices">
          <DeviceList />
        </Section>
      </div>
    </ScrollArea>
  );
}

const DEVICE_REFRESH = 30_000;

const DEVICE_ICONS: Record<string, typeof Laptop> = { macOS: Laptop, Windows: Monitor, Linux: Monitor, Web: Globe, iOS: Smartphone, Android: Smartphone };

/** Every device signed in to this account, with a way to sign the others out. */
function DeviceList() {
  const session = useSession((s) => s.session)!;
  const [devices, setDevices] = useState<Device[] | null>(null);
  const [error, setError] = useState("");
  const [removing, setRemoving] = useState<Device | null>(null);

  const load = useCallback(async () => {
    try {
      setDevices(await api.devices(session));
      setError("");
    } catch (err) {
      setError((err as Error).message);
    }
  }, [session]);

  useEffect(() => {
    void load();
    const timer = setInterval(() => void load(), DEVICE_REFRESH);
    return () => clearInterval(timer);
  }, [load]);

  const remove = async (device: Device) => {
    setDevices((list) => list?.filter((d) => d.id !== device.id) ?? null);
    try {
      await api.removeDevice(session, device.id);
    } catch (err) {
      toast.error(`Couldn't sign out ${device.name}`, { description: (err as Error).message });
    }
    void load();
  };

  if (!devices) return <p className="text-sm text-muted-foreground">{error || "Loading…"}</p>;

  return (
    <>
      <ul className="divide-y rounded-lg border">
        {devices.map((device) => {
          const Icon = DEVICE_ICONS[device.platform] ?? Monitor;
          return (
            <li key={device.id} className="flex items-center gap-3 px-3 py-2.5">
              <div className="relative flex size-8 shrink-0 items-center justify-center rounded-md bg-muted">
                <Icon className="size-4 text-muted-foreground" />
                {device.online && <span className="absolute -right-0.5 -bottom-0.5 size-2.5 rounded-full bg-emerald-500 ring-2 ring-background" />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 text-sm">
                  <span className="truncate">{device.name}</span>
                  {device.current && <span className="shrink-0 rounded bg-muted px-1.5 py-px text-[10px] font-medium text-muted-foreground">This device</span>}
                </div>
                <div className="truncate text-xs text-muted-foreground">
                  {device.platform && `${device.platform} · `}
                  {device.current || device.online ? "Active now" : `Last active ${formatWhen(Date.parse(device.lastSeenAt))}`}
                </div>
              </div>
              {!device.current && (
                <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={() => setRemoving(device)}>
                  Sign out
                </Button>
              )}
            </li>
          );
        })}
      </ul>
      <ConfirmDialog
        open={Boolean(removing)}
        onOpenChange={(open) => !open && setRemoving(null)}
        title={`Sign out ${removing?.name ?? "device"}?`}
        description="It will stop syncing until someone signs in on it again."
        action="Sign out"
        onConfirm={() => removing && void remove(removing)}
      />
    </>
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
