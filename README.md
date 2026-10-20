# reader

A calm, good-looking ebook reader that keeps your library, reading position, highlights,
bookmarks and page styles in sync across devices.

```
server/   Go · Gin · GORM · SQLite   accounts, files and sync
desktop/  Go · Wails v3 · React · shadcn/ui   macOS and Windows app
```

Android and iOS are planned; the desktop frontend keeps platform specifics behind
`desktop/frontend/src/platform` so it can be reused.

## Formats

EPUB, PDF, FB2, CBZ and TXT.

## Running

Server (needs Go 1.25+):

```sh
cd server
go run ./cmd/server
```

| Variable            | Default                |
| ------------------- | ---------------------- |
| `READER_ADDR`       | `:8080`                |
| `READER_DATA_DIR`   | `./data`               |
| `READER_JWT_SECRET` | `dev-secret-change-me` |

Desktop (needs Go 1.25+, Node 20+ and the [Wails v3 CLI](https://v3.wails.io)):

```sh
cd desktop
wails3 dev        # development with hot reload
wails3 build      # production build in desktop/bin
```

The frontend also runs in a plain browser for quick UI work: `cd desktop/frontend && npm run dev`.

## How sync works

Every record (folders, books, progress, annotations, settings) carries a client
`modifiedAt` timestamp and a server-assigned `version`.

- Writes are applied locally first, queued in a persistent outbox and retried until
  the server accepts them. The server keeps the newest `modifiedAt` (last write wins).
- Clients pull `GET /api/sync?since=<version>` for incremental changes.
- `GET /api/events` is a server-sent event stream that tells every signed-in device
  when something changed, so they pull right away.
- Windows on the same machine also share changes instantly over a `BroadcastChannel`.

Reading positions are stored as chapter + fraction (or page for PDF and comics) so
they survive different window sizes and fonts. Highlights are stored as character
offsets within a chapter or PDF page.
