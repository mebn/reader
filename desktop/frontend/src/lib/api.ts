import { remoteUrl, type Session } from "@/platform/types";
import type { Book, Changes, Collection, SyncRecord, User } from "./types";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** REST paths for the simple last-write-wins collections. */
const RECORD_PATHS: Partial<Record<Collection, string>> = {
  folders: "/folders",
  progress: "/progress",
  annotations: "/annotations",
  settings: "/settings",
};

async function request<T>(session: Pick<Session, "serverUrl" | "token">, method: string, path: string, body?: BodyInit | object): Promise<T> {
  const headers: Record<string, string> = {};
  if (session.token) headers.Authorization = `Bearer ${session.token}`;
  if (body && !(body instanceof FormData)) headers["Content-Type"] = "application/json";

  let res: Response;
  try {
    res = await fetch(remoteUrl(session as Session, path), {
      method,
      headers,
      body: body instanceof FormData ? body : body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError("Can't reach the server", 0);
  }
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new ApiError(data.error ?? res.statusText, res.status);
  }
  return res.status === 204 ? (undefined as T) : res.json();
}

export const api = {
  login: (serverUrl: string, email: string, password: string) =>
    request<{ token: string; user: User }>({ serverUrl, token: "" }, "POST", "/auth/login", { email, password }),

  register: (serverUrl: string, email: string, password: string) =>
    request<{ token: string; user: User }>({ serverUrl, token: "" }, "POST", "/auth/register", { email, password }),

  sync: (s: Session, since: number) => request<Changes>(s, "GET", `/sync?since=${since}`),

  put: <T extends SyncRecord>(s: Session, collection: Collection, record: T) => {
    if (collection === "books") return request<T>(s, "PUT", `/books/${record.id}`, record);
    return request<T>(s, "PUT", `${RECORD_PATHS[collection]}/${encodeURIComponent(record.id)}`, record);
  },

  deleteFolder: (s: Session, id: string) => request<void>(s, "DELETE", `/folders/${id}`),

  uploadBook: (s: Session, book: Book, file: Blob, cover?: Blob) => {
    const form = new FormData();
    form.set("meta", JSON.stringify(book));
    form.set("file", file, book.fileName);
    if (cover) form.set("cover", cover, "cover");
    return request<Book>(s, "POST", `/books/${book.id}`, form);
  },

  eventsUrl: (s: Session) => remoteUrl(s, `/events?token=${encodeURIComponent(s.token)}`),
};
