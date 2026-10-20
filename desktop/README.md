# Reader desktop

Wails v3 shell with a React + shadcn/ui frontend.

```
main.go                 app, services, main window, OS file drop
internal/session        signed-in session shared by all windows
internal/windows        reader windows, pin on top, titles
internal/files          serves dropped files and caches books/covers from the server

frontend/src
  platform/             desktop (Wails) and browser implementations
  lib/                  API client, sync engine, settings, actions
  store/                zustand stores
  reader/               format parsers and the page renderers
    formats/            epub, pdf, fb2, cbz, txt
    reflow/             CSS-column paginator for flowing text
    fixed/              fitted pages for PDF and comics
  components/           library, reader and settings UI
  pages/                routes
```

```sh
wails3 dev     # run with hot reload
wails3 build   # build for the current OS
```

Regenerate the Go bindings after changing a service: `wails3 generate bindings -ts -d frontend/bindings`.
