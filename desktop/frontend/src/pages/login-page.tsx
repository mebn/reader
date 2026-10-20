import { useState } from "react";
import { motion } from "motion/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { WindowHeader } from "@/components/common/window-header";
import { api } from "@/lib/api";
import { platform } from "@/platform";
import { DEFAULT_SERVER, useSession } from "@/store/session";

type Mode = "signin" | "signup";

export function LoginPage() {
  const signIn = useSession((s) => s.signIn);
  const previous = useSession((s) => s.session);
  const [mode, setMode] = useState<Mode>("signin");
  const [email, setEmail] = useState(previous?.email ?? "");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const auth = mode === "signin" ? api.login : api.register;
      const { token, user } = await auth(DEFAULT_SERVER, email, password, await platform().device());
      await signIn({ serverUrl: DEFAULT_SERVER, token, email: user.email });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex h-full flex-col">
      <WindowHeader />
      <div className="flex flex-1 items-center justify-center p-6 pb-20">
        <motion.form
          onSubmit={submit}
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, ease: [0.32, 0.72, 0, 1] }}
          className="grid w-full max-w-xs gap-3"
        >
          <h1 className="mb-4 text-center font-serif text-3xl tracking-tight" style={{ fontFamily: '"Literata Variable", serif' }}>
            Reader
          </h1>
          <Input type="email" placeholder="Email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          <Input
            type="password"
            placeholder="Password"
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
            minLength={mode === "signup" ? 8 : undefined}
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {error && <p className="text-center text-sm text-destructive">{error}</p>}
          <Button type="submit" disabled={busy} className="mt-1">
            {mode === "signin" ? "Sign in" : "Create account"}
          </Button>
          <div className="mt-2 flex justify-center text-xs text-muted-foreground">
            <button type="button" className="hover:text-foreground" onClick={() => setMode(mode === "signin" ? "signup" : "signin")}>
              {mode === "signin" ? "Create account" : "I have an account"}
            </button>
          </div>
        </motion.form>
      </div>
    </div>
  );
}
