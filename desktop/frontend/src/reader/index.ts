import { FixedRenderer } from "./fixed/fixed-renderer";
import type { BookDocument } from "./formats";
import { ReflowRenderer } from "./reflow/reflow-renderer";
import type { Renderer, RendererEvents } from "./types";

export type { Appearance, Position, Renderer, TextSelection } from "./types";

export function createRenderer(container: HTMLElement, doc: BookDocument, bookId: string, events: RendererEvents): Renderer {
  return doc.layout === "reflow"
    ? new ReflowRenderer(container, doc, bookId, events)
    : new FixedRenderer(container, doc, events);
}
