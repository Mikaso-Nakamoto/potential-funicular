---
name: shadcn-ui-design-system
description: Build modern, accessible, scalable web applications using the shadcn/ui and Radix UI design system pattern. Covers CSS variables design tokens, Tailwind utility composition, Class Variance Authority (CVA), accessible dialogs, popovers, dropdowns, forms with Zod, and dark mode theming.
---

# shadcn/ui & Radix Design System Skill

This skill guides agents to build modern component-driven user interfaces following the architectural philosophy of shadcn/ui and Radix UI primitives.

## Architectural Principles

1. **Copy/Paste & Ownership over NPM Black Boxes:**
   Components live directly inside your project (e.g., `@/components/ui/*`). You own and customize the code directly.
2. **Accessible Headless Primitives (Radix UI):**
   Radix handles keyboard navigation, focus management, ARIA roles, portal rendering, and screen reader announcements. Tailwind handles the styling.
3. **Design Tokens via CSS Variables:**
   Theme colors are mapped to semantic CSS variables with HSL/OKLCH values, allowing seamless light and dark mode toggling without hardcoding hex values.

---

## 1. Semantic Design Token System

Always reference semantic tokens instead of hardcoded palette colors (`bg-gray-100`, `text-black`):

| Semantic Class | CSS Variable | Intended Usage |
|---|---|---|
| `bg-background` | `--background` | Main page canvas |
| `text-foreground` | `--foreground` | Default readable text |
| `bg-card` / `text-card-foreground` | `--card` | Elevated surface containers |
| `bg-popover` | `--popover` | Floating tooltips, menus, dropdowns |
| `bg-primary` / `text-primary-foreground` | `--primary` | Primary brand action / submit CTA |
| `bg-secondary` | `--secondary` | Less prominent buttons, tags, badges |
| `bg-muted` / `text-muted-foreground` | `--muted` | Subdued backgrounds, placeholders, timestamps |
| `bg-accent` | `--accent` | Hover highlights in menus and list items |
| `border-border` | `--border` | Subtle structural dividers and component edges |
| `ring-ring` | `--ring` | Keyboard focus indicator ring |

---

## 2. Component Variants with CVA (Class Variance Authority)

When authoring custom UI components, use `class-variance-authority` (cva) and `cn()` (clsx + tailwind-merge):

```tsx
import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground shadow hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground shadow-sm hover:bg-destructive/90",
        outline: "border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground",
        secondary: "bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-10 rounded-md px-8",
        icon: "h-9 w-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    return (
      <button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  }
)
Button.displayName = "Button"
```

---

## 3. Accessible Dialogs, Sheets & Modals

### Key Rules:
- **Portaling:** Always render overlay containers into `document.body` via Radix Portal to escape stacking context and overflow clipping.
- **Scroll Lock:** Automatically lock background document scroll when a modal or sheet is open.
- **Focus Trapping:** Automatically trap focus inside the dialog; `Escape` key must dismiss it.
- **Accessibility Description:** Always provide `DialogTitle` and `DialogDescription` for screen readers (use `<VisuallyHidden>` if visually omitted).

---

## 4. Anti-Patterns to Avoid

- **Hardcoding Hex Colors:** Do not use `bg-[#18181b]` or `text-[#f43f5e]` when semantic tokens (`bg-card`, `text-destructive`) exist.
- **Forgetting `focus-visible`:** Never remove default focus outlines (`outline-none`) without adding explicit `focus-visible:ring-2` replacement.
- **Cluttered Class Strings:** Always wrap combined Tailwind strings with `cn(...)` to properly merge overlapping margin/padding utilities.
