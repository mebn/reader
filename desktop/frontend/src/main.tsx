import React from "react";
import ReactDOM from "react-dom/client";
import "@fontsource-variable/inter";
import "@fontsource-variable/literata";
import "@fontsource-variable/literata/wght-italic.css";
import "@fontsource-variable/source-serif-4";
import "@fontsource-variable/lora";
import "@fontsource-variable/merriweather";
import "@fontsource-variable/eb-garamond";
import "@fontsource/atkinson-hyperlegible/400.css";
import "@fontsource/atkinson-hyperlegible/700.css";
import "./index.css";
import { initPlatform } from "./platform";
import { useSession } from "./store/session";
import { App } from "./app";

async function boot() {
  const platform = await initPlatform();
  useSession.setState({ session: await platform.loadSession() });

  ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
}

void boot();
