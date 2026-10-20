import { useEffect } from "react";
import { AnimatePresence } from "motion/react";
import { Route, Router, Switch, useLocation } from "wouter";
import { useHashLocation } from "wouter/use-hash-location";
import { GlobalShortcuts } from "@/components/common/shortcuts-dialog";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useApplyTheme } from "@/hooks/use-theme";
import { typing } from "@/lib/shortcuts";
import { api } from "@/lib/api";
import { sync } from "@/lib/sync";
import { platform } from "@/platform";
import { signedIn, useSession } from "@/store/session";
import { LibraryPage } from "@/pages/library-page";
import { LoginPage } from "@/pages/login-page";
import { ReaderPage } from "@/pages/reader-page";
import { SettingsPage } from "@/pages/settings-page";

export function App() {
  const session = useSession((s) => s.session);
  const dark = useApplyTheme();

  // The header is the window's drag area, buttons included. Dragging the window from a
  // button still ends in a click there; it moved on screen, so that click is dropped.
  useEffect(() => {
    let down: { x: number; y: number } | null = null;
    const press = (e: PointerEvent) => {
      down = (e.target as HTMLElement).closest(".drag-region") ? { x: e.screenX, y: e.screenY } : null;
    };
    const click = (e: MouseEvent) => {
      if (!down || !(e.target as HTMLElement).closest(".drag-region")) return;
      const moved = Math.hypot(e.screenX - down.x, e.screenY - down.y) > 3;
      down = null;
      if (!moved) return;
      e.preventDefault();
      e.stopPropagation();
    };
    window.addEventListener("pointerdown", press, true);
    window.addEventListener("click", click, true);
    return () => {
      window.removeEventListener("pointerdown", press, true);
      window.removeEventListener("click", click, true);
    };
  }, []);

  // No WebKit context menu (Reload, Inspect Element…) outside text fields. The app's own
  // menus open from React handlers, which run before this.
  useEffect(() => {
    const block = (e: MouseEvent) => !typing(e) && e.preventDefault();
    window.addEventListener("contextmenu", block);
    return () => window.removeEventListener("contextmenu", block);
  }, []);

  return (
    <TooltipProvider delayDuration={500}>
      {signedIn(session) ? <SignedIn /> : <LoginPage />}
      <Toaster dark={dark} />
    </TooltipProvider>
  );
}

function SignedIn() {
  const session = useSession((s) => s.session)!;

  useEffect(() => {
    sync.start(session);
    return () => sync.stop();
  }, [session]);

  // Sessions from before devices were tracked get a device once, so they show up in
  // Settings → Account and can be signed out from elsewhere.
  useEffect(() => {
    if (tokenHasDevice(session.token) || registering) return;
    // Once per launch: StrictMode and other windows would otherwise each add a device.
    registering = true;
    void (async () => {
      const { token } = await api.registerDevice(session, await platform().device());
      await useSession.getState().signIn({ ...session, token });
    })().catch((err) => console.warn("device:", err));
  }, [session]);

  return (
    <Router hook={useHashLocation}>
      <Routes />
      <GlobalShortcuts />
    </Router>
  );
}

function Routes() {
  const [location] = useLocation();
  // Folder navigation stays inside the library page so the grid animates in place.
  const key = location.startsWith("/folder/") ? "/" : location;

  return (
    <AnimatePresence mode="popLayout" initial={false}>
      <Switch location={location} key={key}>
        <Route path="/" component={LibraryPage} />
        <Route path="/folder/:folderId" component={LibraryPage} />
        <Route path="/settings" component={SettingsPage} />
        <Route path="/read/:bookId">{(p) => <ReaderPage bookId={p.bookId} />}</Route>
        <Route path="/window/read/:bookId">{(p) => <ReaderPage bookId={p.bookId} standalone />}</Route>
      </Switch>
    </AnimatePresence>
  );
}

let registering = false;

/** Whether a token names its device (the JWT's "jti"); older ones don't. */
function tokenHasDevice(token: string) {
  try {
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return Boolean(payload.jti);
  } catch {
    return true;
  }
}
