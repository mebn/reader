import { useEffect } from "react";
import { AnimatePresence } from "motion/react";
import { Route, Router, Switch, useLocation } from "wouter";
import { useHashLocation } from "wouter/use-hash-location";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useApplyTheme } from "@/hooks/use-theme";
import { sync } from "@/lib/sync";
import { signedIn, useSession } from "@/store/session";
import { LibraryPage } from "@/pages/library-page";
import { LoginPage } from "@/pages/login-page";
import { ReaderPage } from "@/pages/reader-page";
import { SettingsPage } from "@/pages/settings-page";

export function App() {
  const session = useSession((s) => s.session);
  const dark = useApplyTheme();

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

  return (
    <Router hook={useHashLocation}>
      <Routes />
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
