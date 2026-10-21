import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { ArrowLeft, Loader2, Mail } from "lucide-react";
import { WindowHeader } from "@/components/common/window-header";
import { FloatingObjects } from "@/components/login/floating-objects";
import { HeroBook } from "@/components/login/hero-book";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";
import { platform, type Session } from "@/platform";
import { DEFAULT_SERVER, useSession } from "@/store/session";

type Mode = "signin" | "signup";

/** Signs in and lands on the library, not on whatever page the last session ended on. */
async function enter(signIn: (session: Session) => Promise<void>, session: Session) {
  // A window that only shows one book stays on it.
  if (!location.hash.startsWith("#/window/")) location.hash = "#/";
  await signIn(session);
}

const EASE = [0.22, 1, 0.36, 1] as const;
const TITLE = "Reader";
const SUBTITLE = "Every book, everywhere.";
const GOOGLE_POLL_MS = 1500;
const GOOGLE_TIMEOUT_MS = 10 * 60 * 1000;

export function LoginPage() {
  const [view, setView] = useState<"choose" | "email">("choose");

  return (
    <div className="relative h-full overflow-hidden bg-[#fbf7ee] dark:bg-[#171411]">
      <Backdrop />
      <FloatingObjects />
      <WindowHeader className="absolute inset-x-0 top-0 z-50" />

      <div className="relative z-10 flex h-full flex-col items-center overflow-y-auto px-6">
        <div className="my-auto flex w-full max-w-sm flex-col items-center py-14">
          <HeroBook />
          <Headline />
          {/* Both views share one cell, so the slot keeps the taller one's height and nothing above it moves. */}
          <div className="mt-8 grid w-full">
            <Panel active={view === "choose"}>
              <Choose onEmail={() => setView("email")} />
            </Panel>
            <Panel active={view === "email"}>
              <EmailForm active={view === "email"} onBack={() => setView("choose")} />
            </Panel>
          </div>
        </div>
      </div>
    </div>
  );
}

/** Soft colour that slowly wanders behind everything. */
function Backdrop() {
  const calm = useReducedMotion();
  const blob = (className: string, x: number[], y: number[], duration: number) => (
    <motion.div
      className={`absolute rounded-full blur-3xl ${className}`}
      animate={calm ? undefined : { x, y, scale: [1, 1.15, 1] }}
      transition={{ duration, repeat: Infinity, ease: "easeInOut" }}
    />
  );
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
      <div className="absolute inset-0 bg-[radial-gradient(120%_80%_at_50%_0%,#fff7e6_0%,transparent_60%)] dark:bg-[radial-gradient(120%_80%_at_50%_0%,#2c241d_0%,transparent_60%)]" />
      {blob("-left-24 top-[8%] size-[360px] bg-[#f0b98a]/45 dark:bg-[#c9532c]/20", [0, 60, 0], [0, 40, 0], 16)}
      {blob("-right-20 top-[30%] size-[380px] bg-[#9ec4b0]/45 dark:bg-[#46607f]/25", [0, -50, 0], [0, -30, 0], 19)}
      {blob("left-[30%] -bottom-40 size-[420px] bg-[#f3d58a]/45 dark:bg-[#e0a93c]/12", [0, 40, 0], [0, -40, 0], 22)}
      {/* A faint ruled-paper texture. */}
      <div className="absolute inset-0 opacity-[0.35] [background-image:repeating-linear-gradient(0deg,transparent_0,transparent_31px,rgb(120_100_80/0.08)_31px,rgb(120_100_80/0.08)_32px)] dark:opacity-60" />
    </div>
  );
}

function Headline() {
  return (
    <div className="mt-7 text-center">
      <h1 className="font-serif text-[clamp(38px,6vw,52px)] leading-none font-medium tracking-tight" style={{ fontFamily: '"Literata Variable", serif' }} aria-label={TITLE}>
        {[...TITLE].map((letter, i) => (
          <span key={i} className="inline-block overflow-hidden pb-2 align-bottom" aria-hidden>
            <motion.span
              className="inline-block"
              initial={{ y: "110%", opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{ duration: 0.7, ease: EASE, delay: 0.45 + i * 0.06 }}
            >
              {letter}
            </motion.span>
          </span>
        ))}
      </h1>
      <motion.p
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, ease: EASE, delay: 0.95 }}
        className="mt-2 text-base text-muted-foreground"
      >
        {SUBTITLE}
      </motion.p>
    </div>
  );
}

/** One of the views that trade places in the slot under the title. */
function Panel({ active, children }: { active: boolean; children: React.ReactNode }) {
  return (
    <motion.div
      className="col-start-1 row-start-1"
      initial={false}
      animate={{ opacity: active ? 1 : 0, y: active ? 0 : -10, scale: active ? 1 : 0.98 }}
      transition={{ duration: 0.35, ease: EASE }}
      style={{ pointerEvents: active ? "auto" : "none" }}
      inert={!active}
    >
      {children}
    </motion.div>
  );
}

/** Rises into place; each step of a column staggers after the last. */
const rise = (i: number) => ({
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: { duration: 0.6, ease: EASE, delay: 0.9 + i * 0.1 } },
});

function Choose({ onEmail }: { onEmail: () => void }) {
  const signIn = useSession((s) => s.signIn);
  const [waiting, setWaiting] = useState(false);
  const [error, setError] = useState("");
  const stop = useRef<() => void>(undefined);

  useEffect(() => () => stop.current?.(), []);

  // The browser does the signing in; we poll the server until it has the result.
  const google = async () => {
    let cancelled = false;
    stop.current = () => (cancelled = true);
    setError("");
    setWaiting(true);
    try {
      const { url, state, secret } = await api.googleStart(DEFAULT_SERVER, await platform().device());
      platform().openUrl(url);
      const deadline = Date.now() + GOOGLE_TIMEOUT_MS;
      while (!cancelled && Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, GOOGLE_POLL_MS));
        if (cancelled) return;
        const done = await api.googlePoll(DEFAULT_SERVER, state, secret);
        if (done) {
          await enter(signIn, { serverUrl: DEFAULT_SERVER, token: done.token, email: done.user.email });
          return;
        }
      }
      if (!cancelled) setError("Google sign-in timed out. Try again.");
    } catch (err) {
      if (!cancelled) setError((err as Error).message);
    } finally {
      if (!cancelled) setWaiting(false);
    }
  };

  return (
    <div className="grid w-full gap-3">
      <motion.div {...rise(0)}>
        <button
          type="button"
          onClick={waiting ? undefined : google}
          disabled={waiting}
          className="group flex h-12 w-full items-center justify-center gap-3 rounded-full border border-black/5 bg-white text-[15px] font-semibold text-[#1f1f1f] shadow-[0_8px_24px_-10px_rgb(60_40_20/0.35)] transition-all hover:-translate-y-0.5 hover:shadow-[0_14px_30px_-10px_rgb(60_40_20/0.45)] active:translate-y-0 active:scale-[0.99] disabled:translate-y-0 disabled:cursor-default"
        >
          {waiting ? <Loader2 className="size-5 animate-spin text-muted-foreground" /> : <GoogleMark />}
          {waiting ? "Waiting for Google…" : "Continue with Google"}
        </button>
        <AnimatePresence>
          {waiting && (
            <motion.button
              type="button"
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="mx-auto mt-2 block overflow-hidden text-xs text-muted-foreground hover:text-foreground"
              onClick={() => {
                stop.current?.();
                setWaiting(false);
              }}
            >
              Finish in your browser, or cancel
            </motion.button>
          )}
        </AnimatePresence>
      </motion.div>

      <motion.div {...rise(1)}>
        <button
          type="button"
          onClick={onEmail}
          className="flex h-12 w-full items-center justify-center gap-3 rounded-full bg-[#2b2622] text-[15px] font-semibold text-white shadow-[0_8px_24px_-10px_rgb(30_20_10/0.6)] transition-all hover:-translate-y-0.5 hover:bg-[#38312b] active:translate-y-0 active:scale-[0.99] dark:bg-white/10 dark:hover:bg-white/15"
        >
          <Mail className="size-[18px]" />
          Continue with email
        </button>
      </motion.div>

      {error && (
        <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="text-center text-sm text-destructive">
          {error}
        </motion.p>
      )}
    </div>
  );
}

function EmailForm({ active, onBack }: { active: boolean; onBack: () => void }) {
  const signIn = useSession((s) => s.signIn);
  const previous = useSession((s) => s.session);
  const [mode, setMode] = useState<Mode>("signin");
  const [email, setEmail] = useState(previous?.email ?? "");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const emailRef = useRef<HTMLInputElement>(null);

  // Focus the first field once this view has taken its turn.
  useEffect(() => {
    if (active) emailRef.current?.focus({ preventScroll: true });
  }, [active]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const auth = mode === "signin" ? api.login : api.register;
      const { token, user } = await auth(DEFAULT_SERVER, email, password, await platform().device());
      await enter(signIn, { serverUrl: DEFAULT_SERVER, token, email: user.email });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="grid w-full gap-3">
      <Input
        type="email"
        placeholder="Email"
        autoComplete="email"
        ref={emailRef}
        required
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="h-11 rounded-full bg-white/80 px-4 backdrop-blur dark:bg-white/5"
      />
      <Input
        type="password"
        placeholder="Password"
        autoComplete={mode === "signin" ? "current-password" : "new-password"}
        minLength={mode === "signup" ? 8 : undefined}
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="h-11 rounded-full bg-white/80 px-4 backdrop-blur dark:bg-white/5"
      />
      {error && <p className="text-center text-sm text-destructive">{error}</p>}
      <Button type="submit" disabled={busy} className="h-12 rounded-full text-[15px] font-semibold">
        {busy && <Loader2 className="animate-spin" />}
        {mode === "signin" ? "Sign in" : "Create account"}
      </Button>
      <div className="mt-1 flex items-center justify-between text-xs text-muted-foreground">
        <button type="button" className="flex items-center gap-1 hover:text-foreground" onClick={onBack}>
          <ArrowLeft className="size-3.5" />
          Back
        </button>
        <button type="button" className="hover:text-foreground" onClick={() => setMode(mode === "signin" ? "signup" : "signin")}>
          {mode === "signin" ? "Create account" : "I have an account"}
        </button>
      </div>
    </form>
  );
}

function GoogleMark() {
  return (
    <svg viewBox="0 0 48 48" className="size-5" aria-hidden>
      <path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.9 6.1C12.4 13.6 17.7 9.5 24 9.5z" />
      <path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.5 5.8c4.4-4.1 7.1-10.1 7.1-17.5z" />
      <path fill="#FBBC05" d="M10.5 28.7a14.5 14.5 0 0 1 0-9.4l-7.9-6.1a24 24 0 0 0 0 21.6l7.9-6.1z" />
      <path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.5-5.8c-2.1 1.4-4.8 2.3-8.4 2.3-6.3 0-11.6-4.1-13.5-9.8l-7.9 6.1C6.5 42.6 14.6 48 24 48z" />
    </svg>
  );
}
