import type { ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";

/** One loop, in seconds: the book opens, turns three pages, and closes again. */
const LOOP = 12;
const TIMES = {
  // Opens by .24, stays open until .78, closed again by .94.
  cover: [0, 0.08, 0.24, 0.78, 0.94, 1],
  shift: [0, 0.08, 0.24, 0.78, 0.94, 1],
};
const FLIPPED = -168;

function leafTimes(i: number) {
  const start = 0.3 + i * 0.12;
  return [0, start, start + 0.11, 0.78, 0.94, 1];
}

/** Ruled lines standing in for text, as widths in percent of the page. */
function Lines({ rows, heading }: { rows: number[]; heading?: boolean }) {
  return (
    <div className="absolute inset-x-[16%] top-[14%] flex flex-col" style={{ gap: "calc(var(--w) * 0.085)" }}>
      {heading && <div className="w-[46%] rounded-full bg-[#d9663f]/70" style={{ height: "calc(var(--w) * 0.05)" }} />}
      {rows.map((w, i) => (
        <div key={i} className="rounded-full bg-[#46607f]/20" style={{ width: `${w}%`, height: "calc(var(--w) * 0.032)" }} />
      ))}
    </div>
  );
}

const RIGHT_ROWS = [100, 94, 100, 88, 100, 62];
const LEFT_ROWS = [96, 100, 84, 100, 92, 48];

/** A sheet that turns about the spine: its front faces right, its back faces left once turned. */
function Leaf({ index, front, back, frontClass, backClass }: { index: number; front: ReactNode; back: ReactNode; frontClass: string; backClass: string }) {
  const calm = useReducedMotion();
  const times = leafTimes(index);
  const rest = 4 - index; // top of the right-hand stack
  const turned = index + 1; // top of the left-hand stack
  return (
    <motion.div
      className="absolute inset-0 [transform-style:preserve-3d]"
      style={{ transformOrigin: "left center" }}
      animate={calm ? undefined : { rotateY: [0, 0, FLIPPED + index * 2, FLIPPED + index * 2, 0, 0], z: [rest, rest, turned, turned, rest, rest] }}
      transition={{ duration: LOOP, times, repeat: Infinity, ease: "easeInOut" }}
    >
      <div className={`absolute inset-0 [backface-visibility:hidden] ${frontClass}`}>{front}</div>
      <div className={`absolute inset-0 [backface-visibility:hidden] [transform:rotateY(180deg)] ${backClass}`}>{back}</div>
    </motion.div>
  );
}

/** A closed book that opens, turns its pages and closes, in CSS 3D. */
export function HeroBook() {
  const calm = useReducedMotion();
  const loop = { duration: LOOP, repeat: Infinity, ease: "easeInOut" as const };

  return (
    <motion.div
      initial={{ opacity: 0, y: 24, scale: 0.9 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1], delay: 0.1 }}
      className="relative flex shrink-0 items-center justify-center [perspective:1400px]"
      style={{ ["--w" as string]: "clamp(72px, 14vh, 128px)", width: "calc(var(--w) * 2.2)", height: "calc(var(--w) * 1.46)" }}
    >
      {/* Rests on the page: floats gently as a whole. */}
      <motion.div
        animate={calm ? undefined : { y: [0, -6, 0] }}
        transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
        className="relative [transform-style:preserve-3d]"
        style={{ width: "var(--w)", height: "calc(var(--w) * 1.46)" }}
      >
        <motion.div
          className="absolute inset-0 [transform-style:preserve-3d]"
          style={{ rotateX: 8, rotateY: -16 }}
        >
          <motion.div
            className="absolute inset-0 [transform-style:preserve-3d]"
            animate={calm ? undefined : { x: ["0%", "0%", "50%", "50%", "0%", "0%"] }}
            transition={{ ...loop, times: TIMES.shift }}
          >
            {/* Shadow on the table. */}
            <motion.div
              className="absolute inset-x-0 -bottom-[9%] h-[9%] origin-left rounded-full bg-black/30 blur-md dark:bg-black/60"
              style={{ transformOrigin: "left center" }}
              animate={calm ? undefined : { scaleX: [1, 1, 1.9, 1.9, 1, 1], x: ["0%", "0%", "-48%", "-48%", "0%", "0%"] }}
              transition={{ ...loop, times: TIMES.cover }}
            />

            {/* The page block under the leaves, always at rest on the right. */}
            <div className="absolute inset-0 rounded-r-[6%] bg-[#f6efe1] shadow-[2px_3px_0_#d8cdb9,4px_6px_0_#c9bda6]" style={{ transform: "translateZ(1px)" }}>
              <Lines rows={RIGHT_ROWS} heading />
            </div>

            {[0, 1, 2].map((i) => (
              <Leaf
                key={i}
                index={i}
                frontClass="rounded-r-[6%] bg-[#fbf6ec]"
                backClass="rounded-l-[6%] bg-[#f6efe1]"
                front={<Lines rows={RIGHT_ROWS.map((w) => w - i * 3)} heading={i === 1} />}
                back={<Lines rows={LEFT_ROWS.map((w) => w - i * 4)} />}
              />
            ))}

            {/* The cover, with the bookmark ribbon, and the endpaper inside it. */}
            <motion.div
              className="absolute inset-0 [transform-style:preserve-3d]"
              style={{ transformOrigin: "left center" }}
              animate={calm ? undefined : { rotateY: [0, 0, FLIPPED - 4, FLIPPED - 4, 0, 0], z: [6, 6, 0, 0, 6, 6] }}
              transition={{ ...loop, times: TIMES.cover }}
            >
              <div className="absolute inset-0 overflow-hidden rounded-[6%_8%_8%_6%] bg-gradient-to-br from-[#f7f1e6] to-[#e8decc] shadow-[0_1px_0_rgb(255_255_255/0.6)_inset] [backface-visibility:hidden]">
                <div className="absolute inset-y-0 left-0 w-[15%] bg-gradient-to-r from-[#cfc3ae] to-[#e0d6c3]" />
                <div className="absolute inset-y-0 left-[15%] w-px bg-white/70" />
                <div className="absolute left-[30%] top-[34%] rounded-full bg-[#3d3630]/85" style={{ width: "56%", height: "calc(var(--w) * 0.055)" }} />
                <div className="absolute left-[30%] top-[34%] rounded-full bg-[#3d3630]/35" style={{ width: "36%", height: "calc(var(--w) * 0.055)", marginTop: "calc(var(--w) * 0.11)" }} />
                <div className="absolute right-[12%] top-0 h-[30%] w-[12%] bg-gradient-to-b from-[#e2744a] to-[#c9532c] [clip-path:polygon(0_0,100%_0,100%_100%,50%_82%,0_100%)]" />
              </div>
              <div className="absolute inset-0 [backface-visibility:hidden] [transform:rotateY(180deg)] overflow-hidden rounded-l-[6%] bg-[#3d3630]">
                <div className="absolute inset-[12%] rounded-[4%] border border-[#f4ecde]/20" />
                <div className="absolute left-1/2 top-1/2 h-[26%] w-[46%] -translate-x-1/2 -translate-y-1/2 rounded-[8%] bg-[#f4ecde]/90" />
              </div>
            </motion.div>
          </motion.div>
        </motion.div>
      </motion.div>
    </motion.div>
  );
}
