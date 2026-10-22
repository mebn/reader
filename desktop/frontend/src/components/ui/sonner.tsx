import { Toaster as Sonner, type ToasterProps } from "sonner"

const Toaster = ({ dark, ...props }: ToasterProps & { dark: boolean }) => {
  return (
    <Sonner
      theme={dark ? "dark" : "light"}
      className="toaster group"
      position="bottom-left"
      style={
        {
          "--normal-bg": "var(--popover)",
          "--normal-text": "var(--popover-foreground)",
          "--normal-border": "var(--border)",
          "--border-radius": "var(--radius)",
        } as React.CSSProperties
      }
      {...props}
    />
  )
}

export { Toaster }
