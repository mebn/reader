import type { ReactNode } from "react";

/** Flat, book-themed sprites for the sign-in backdrop. Each fills the width it is given. */

export interface BookColors {
  cover: string;
  spine: string;
  accent: string;
}

export const BOOKS = {
  clay: { cover: "#d9663f", spine: "#b9502d", accent: "#f7e3b5" },
  sage: { cover: "#6f9a7e", spine: "#567d65", accent: "#f4efe2" },
  ink: { cover: "#46607f", spine: "#344b67", accent: "#f2c46d" },
  mustard: { cover: "#e0a93c", spine: "#bf8a24", accent: "#2f2a25" },
  plum: { cover: "#7d6590", spine: "#624d75", accent: "#f4efe2" },
  cream: { cover: "#f4ecde", spine: "#d9cdb8", accent: "#d9663f" },
} satisfies Record<string, BookColors>;

function Svg({ viewBox, children }: { viewBox: string; children: ReactNode }) {
  return (
    <svg viewBox={viewBox} className="block h-auto w-full overflow-visible" aria-hidden>
      {children}
    </svg>
  );
}

const SHADOW = "drop-shadow(0 10px 14px rgb(40 30 20 / 0.28))";

export function ClosedBook({ cover, spine, accent }: BookColors) {
  return (
    <Svg viewBox="0 0 100 140">
      <g style={{ filter: SHADOW }}>
        <rect x="4" y="4" width="92" height="132" rx="9" fill={cover} />
        <path d="M13 4h9v132h-9a9 9 0 0 1-9-9V13a9 9 0 0 1 9-9z" fill={spine} />
        <rect x="26" y="4" width="2" height="132" fill="#fff" opacity="0.28" />
        <rect x="40" y="46" width="42" height="7" rx="3.5" fill={accent} opacity="0.95" />
        <rect x="40" y="60" width="28" height="7" rx="3.5" fill={accent} opacity="0.55" />
        <path d="M70 4h12v30l-6-5-6 5z" fill={accent} opacity="0.9" />
      </g>
    </Svg>
  );
}

export function BookStack() {
  const rows = [
    { y: 74, w: 150, x: 0, c: BOOKS.ink },
    { y: 44, w: 128, x: 12, c: BOOKS.clay },
    { y: 14, w: 138, x: 4, c: BOOKS.sage },
  ];
  return (
    <Svg viewBox="0 0 150 106">
      <g style={{ filter: SHADOW }}>
        {rows.map(({ y, w, x, c }) => (
          <g key={y}>
            <rect x={x} y={y} width={w} height="28" rx="5" fill={c.cover} />
            <rect x={x + w - 12} y={y} width="12" height="28" rx="4" fill="#f4ecde" opacity="0.92" />
            <rect x={x + 14} y={y + 8} width="34" height="5" rx="2.5" fill={c.accent} opacity="0.85" />
            <rect x={x + 14} y={y + 17} width="20" height="4" rx="2" fill={c.accent} opacity="0.5" />
          </g>
        ))}
      </g>
    </Svg>
  );
}

export function OpenBook() {
  return (
    <Svg viewBox="0 0 170 116">
      <g style={{ filter: SHADOW }}>
        <path d="M6 14q40-12 79 6v90q-39-18-79-6z" fill="#e8dcc6" />
        <path d="M164 14q-40-12-79 6v90q39-18 79-6z" fill="#e8dcc6" />
        <path d="M10 10q38-11 75 6v88q-37-16-75-6z" fill="#fbf6ec" />
        <path d="M160 10q-38-11-75 6v88q37-16 75-6z" fill="#f6efe1" />
        {[28, 42, 56, 70].map((y, i) => (
          <g key={y} fill="#46607f" opacity={0.22}>
            <rect x="24" y={y} width={i === 3 ? 30 : 48} height="4" rx="2" />
            <rect x="104" y={y - 2} width={i === 0 ? 34 : 42} height="4" rx="2" />
          </g>
        ))}
        <rect x="104" y="80" width="38" height="4" rx="2" fill="#46607f" opacity="0.22" />
        <rect x="83" y="16" width="4" height="92" fill="#000" opacity="0.08" />
      </g>
    </Svg>
  );
}

export function Bookmark({ color = "#d9663f" }: { color?: string }) {
  return (
    <Svg viewBox="0 0 40 100">
      <g style={{ filter: SHADOW }}>
        <path d="M4 0h32v100l-16-18L4 100z" fill={color} />
        <path d="M10 0h4v84l-4 4z" fill="#fff" opacity="0.22" />
      </g>
    </Svg>
  );
}

export function Glasses() {
  return (
    <Svg viewBox="0 0 130 52">
      <g fill="none" stroke="#3a322b" strokeWidth="5" strokeLinecap="round" style={{ filter: SHADOW }}>
        <circle cx="32" cy="28" r="20" fill="#bfe0e8" fillOpacity="0.45" />
        <circle cx="98" cy="28" r="20" fill="#bfe0e8" fillOpacity="0.45" />
        <path d="M52 26q13-8 26 0" />
        <path d="M12 24L3 14M118 24l9-10" />
      </g>
    </Svg>
  );
}

export function Cup() {
  return (
    <Svg viewBox="0 0 100 100">
      <g style={{ filter: SHADOW }}>
        <path d="M26 6q-8 10 0 18M46 2q-8 12 0 22M66 6q-8 10 0 18" fill="none" stroke="#fff" strokeOpacity="0.7" strokeWidth="4" strokeLinecap="round" />
        <path d="M14 34h62v22a26 26 0 0 1-26 26h-10a26 26 0 0 1-26-26z" fill="#f4ecde" />
        <path d="M76 42h6a10 10 0 0 1 0 20h-8" fill="none" stroke="#f4ecde" strokeWidth="7" strokeLinecap="round" />
        <rect x="14" y="34" width="62" height="9" rx="4" fill="#6b4a36" />
        <ellipse cx="45" cy="92" rx="38" ry="5" fill="#d9cdb8" />
      </g>
    </Svg>
  );
}

export function Pencil() {
  return (
    <Svg viewBox="0 0 36 130">
      <g style={{ filter: SHADOW }}>
        <rect x="4" y="12" width="28" height="80" rx="4" fill="#e0a93c" />
        <rect x="14" y="12" width="8" height="80" fill="#bf8a24" opacity="0.5" />
        <path d="M4 92h28l-14 30z" fill="#f4ecde" />
        <path d="M13 111h10l-5 11z" fill="#3a322b" />
        <rect x="4" y="2" width="28" height="12" rx="4" fill="#d9663f" />
        <rect x="4" y="12" width="28" height="5" fill="#cfd4d9" />
      </g>
    </Svg>
  );
}

export function Page() {
  return (
    <Svg viewBox="0 0 100 130">
      <g style={{ filter: SHADOW }}>
        <path d="M6 4h72l16 16v106H6z" fill="#fbf6ec" />
        <path d="M78 4v16h16z" fill="#e8dcc6" />
        {[38, 52, 66, 80, 94].map((y, i) => (
          <rect key={y} x="18" y={y} width={i === 4 ? 30 : 62} height="4" rx="2" fill="#46607f" opacity="0.2" />
        ))}
        <rect x="18" y="20" width="36" height="6" rx="3" fill="#d9663f" opacity="0.7" />
      </g>
    </Svg>
  );
}
