import { fontFamily, resolveBackground, type ReaderSettings } from "@/lib/settings";

const SAMPLE = [
  "It was a bright cold day in April, and the clocks were striking thirteen. The hallway smelt of boiled cabbage and old rag mats.",
  "At one end of it a coloured poster, too large for indoor display, had been tacked to the wall.",
];

/** A small page that shows how the current settings will read. */
export function SettingsPreview({ settings, dark }: { settings: ReaderSettings; dark: boolean }) {
  const bg = resolveBackground(settings, dark);

  return (
    <div
      className="flex aspect-[3/4] flex-col overflow-hidden rounded-xl shadow-sm ring-1 ring-black/5 transition-colors duration-300 dark:ring-white/10"
      style={{ background: bg.color, padding: `24px ${settings.sideMargin}%` }}
    >
      {/* Cut off inside the padding, so the page keeps its bottom margin like a real one. */}
      <div
        className="book-content min-h-0 flex-1 overflow-hidden"
        style={
          {
            "--reader-font": fontFamily(settings.font),
            "--reader-size": `${settings.fontSize * 0.8}px`,
            "--reader-leading": settings.lineHeight,
            "--reader-align": settings.align,
            "--reader-hyphens": settings.hyphenate ? "auto" : "manual",
            "--reader-text": bg.text,
            "--reader-weight": settings.weight,
            "--reader-tracking": `${settings.tracking}em`,
            "--reader-paragraph": `${settings.paragraphSpacing}em`,
            userSelect: "none",
          } as React.CSSProperties
        }
        lang="en"
      >
        <h3>One</h3>
        {SAMPLE.map((p) => (
          <p key={p}>{p}</p>
        ))}
      </div>
    </div>
  );
}
