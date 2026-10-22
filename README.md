# reader

A calm, good-looking ebook reader that keeps your library, reading position, highlights,
bookmarks and page styles in sync across devices.

```
backend/  Go · Gin · GORM · SQLite   accounts, files and sync
desktop/  Go · Wails v3 · React · shadcn/ui   macOS and Windows app
ios/      SwiftUI · TextKit · PDFKit          iPhone and iPad app (iOS 26, Liquid Glass)
```

Android is planned.

## Formats

EPUB, PDF, FB2, CBZ and TXT.

## Running

`make desktop`, `make ios`, `make desktop-ios` or `make all` start the server and the apps
together (`make server` for just the server); see the Makefile for the rest. Pick a
simulator with `SIM="iPhone 17 Pro"`. Ctrl-C stops everything, including the server.

Backend (needs Go 1.25+):

```sh
cd backend
go run ./cmd/server
```

| Variable            | Default                |
| ------------------- | ---------------------- |
| `READER_ADDR`       | `:8080`                |
| `READER_DATA_DIR`   | `./data`               |
| `READER_JWT_SECRET` | `dev-secret-change-me` |

Sign in with Google is offered once the server has an OAuth client (Google Cloud console →
APIs & Services → Credentials → OAuth client ID, type *Web application*). Add
`<READER_PUBLIC_URL>/api/auth/google/callback` as an authorised redirect URI, e.g.
`http://localhost:8080/api/auth/google/callback` while developing.

| Variable                     | Default                | |
| ---------------------------- | ---------------------- | - |
| `READER_GOOGLE_CLIENT_ID`    |                        | OAuth client id |
| `READER_GOOGLE_CLIENT_SECRET`|                        | OAuth client secret |
| `READER_PUBLIC_URL`          | `http://localhost` + `READER_ADDR` | where Google sends the browser back to |

The app opens Google in the system browser and the server finishes the sign-in (authorisation
code with PKCE, ID token verified with `coreos/go-oidc`), so the secret never leaves the server.
An existing account with the same verified email is linked; otherwise one is created.

Desktop (needs Go 1.25+, Node 20+ and the [Wails v3 CLI](https://v3.wails.io)):

```sh
cd desktop
wails3 dev        # development with hot reload
wails3 build      # production build in desktop/bin
```

The frontend also runs in a plain browser for quick UI work: `cd desktop/frontend && npm run dev`.

The app talks to the server at `VITE_SERVER_URL`, set when building (default
`http://localhost:8080`), e.g. `VITE_SERVER_URL=https://reader.example.com wails3 build`.

iOS (needs Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
cd ios
xcodegen generate     # creates Reader.xcodeproj from project.yml
open Reader.xcodeproj
```

The server is fixed at build time by the `READER_SERVER_URL` build setting (default
`http://localhost:8080`, which a simulator reaches but a phone doesn't), e.g.
`xcodebuild -scheme Reader READER_SERVER_URL=https://reader.example.com`.

The iOS app is fully native: EPUB, FB2 and TXT are parsed and paginated with TextKit,
PDF uses PDFKit and comics are shown as images. Highlights count character offsets the
same way the desktop's DOM does, so they line up on both; `ReaderTests` checks this
against WebKit when run with `TEST_RUNNER_BOOKS_DIR` pointing at a folder of EPUBs.
PDF highlights are an exception: PDFKit and pdf.js extract page text slightly
differently, so iOS finds a PDF highlight from another device by its text when the
offsets don't match.

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
