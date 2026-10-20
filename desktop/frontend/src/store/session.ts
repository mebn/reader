import { create } from "zustand";
import { platform, type Session } from "@/platform";

interface SessionState {
  session: Session | null;
  signIn(session: Session): Promise<void>;
  signOut(): Promise<void>;
}

export const DEFAULT_SERVER = "http://localhost:8080";

export const useSession = create<SessionState>()((set) => ({
  session: null,
  async signIn(session) {
    await platform().saveSession(session);
    set({ session });
  },
  async signOut() {
    await platform().clearSession();
    set({ session: null });
  },
}));

export function signedIn(session: Session | null): session is Session {
  return Boolean(session?.token);
}
