import { motion, type HTMLMotionProps } from "motion/react";
import { cn } from "@/lib/utils";

type Variant = "fade" | "slide" | "zoom";

const VARIANTS: Record<Variant, HTMLMotionProps<"div">> = {
  fade: {
    initial: { opacity: 0, scale: 1.015 },
    animate: { opacity: 1, scale: 1 },
    exit: { opacity: 0, scale: 0.985 },
  },
  slide: {
    initial: { opacity: 0, x: 24 },
    animate: { opacity: 1, x: 0 },
    exit: { opacity: 0, x: 24 },
  },
  zoom: {
    initial: { opacity: 0, scale: 0.97 },
    animate: { opacity: 1, scale: 1 },
    exit: { opacity: 0, scale: 0.97 },
  },
};

/** Full-window route container with an enter/exit transition. */
export function Page({ variant = "fade", className, ...props }: HTMLMotionProps<"div"> & { variant?: Variant }) {
  return (
    <motion.div
      {...VARIANTS[variant]}
      transition={{ duration: 0.32, ease: [0.32, 0.72, 0, 1] }}
      className={cn("absolute inset-0 flex flex-col overflow-hidden bg-background", className)}
      {...props}
    />
  );
}
