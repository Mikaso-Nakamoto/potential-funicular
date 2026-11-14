---
name: refactoring-ui
description: Design practical, polished user interfaces using developer-first design rules from Refactoring UI (Steve Schoger & Adam Wathan). Covers visual hierarchy via weight/contrast, avoiding pure black, layered shadows, double borders, grayscale-first workflow, spacing scales, and micro-layout refinement.
---

# Refactoring UI Design Skill

This skill translates the tactical, high-impact design principles from *Refactoring UI* into actionable rules for AI coding agents.

## Core Philosophy
Designing from a developer's perspective means using systems, constraints, and deliberate rules rather than relying on abstract artistic intuition.

---

## 1. Visual Hierarchy: It's Not Just Font Size

Do not rely solely on font size to show importance. Using too many font sizes makes an interface chaotic.

### The Contrast & Weight Rule:
- **Primary Information:** Darker color (`text-slate-900` or `text-zinc-100`), heavier weight (`font-semibold` or `font-medium`).
- **Secondary Information:** Muted color (`text-slate-500` or `text-zinc-400`), regular weight (`font-normal`), slightly smaller size.
- **Tertiary / Metadata:** Even lighter tint (`text-slate-400` or `text-zinc-500`), uppercase with letter-spacing (`text-xs uppercase tracking-wider`).

---

## 2. Never Use Pure Black (`#000000`)

Pure black on white creates harsh, jarring contrast that causes visual vibration and eye strain.

### What to Use Instead:
- In Light Mode: Use deep slate/zinc tones: `#0F172A` (slate-900) or `#18181B` (zinc-900).
- Tinted Neutrals: Infuse your gray scale with a tiny hint of your primary color (e.g., cool blue-gray for tech/SaaS, warm beige-gray for editorial/lifestyle).
- In Dark Mode: Never use pitch black `#000000` for surface containers. Use layered elevation:
  - Background Canvas: `#09090B`
  - Cards/Containers: `#18181B`
  - Popovers/Modals: `#27272A`

---

## 3. Whitespace Over Lines & Borders

Amateur designs rely on border lines everywhere to divide content, leading to noisy, cluttered screens.

### Better Alternatives:
1. **Use generous spacing:** Double the gap between distinct sections (`gap-8` instead of `gap-4`).
2. **Use subtle background fills:** Distinguish table headers, sidebars, or alternate rows using a very soft tint (`bg-slate-50` or `bg-zinc-900/50`) instead of hard lines.
3. **Double Borders for High-End Glass / Depth:**
   On dark cards, use an inner highlight border plus an outer drop shadow:
   ```html
   <div class="rounded-xl bg-zinc-900/80 border border-white/10 shadow-2xl backdrop-blur-md">
     ...
   </div>
   ```

---

## 4. Work in Grayscale First

Never start a UI by picking a rainbow of colors.

1. **Build layout, typography, spacing, and contrast entirely in black, white, and shades of gray.**
2. Once the visual hierarchy works with zero color, introduce **one single accent color** for primary CTAs and active states.
3. Add semantic accent colors (success green, warning amber, error red) strictly for feedback states.

---

## 5. Don't Shrink Icons to Fit Text

When pairing an icon with text:
- Do not let the icon dominate or look misaligned.
- Set icon sizes to match text line-height (e.g., `size-4` for `text-sm`, `size-5` for `text-base`).
- Use `inline-flex items-center gap-1.5` to ensure perfect optical vertical centering.

---

## 6. Table & Data Density Best Practices

- Right-align numbers and currency so decimal points align vertically.
- Left-align textual headers with their text content.
- Center-align status badges and boolean icons.
- Mute column headers (`text-xs font-semibold uppercase tracking-wider text-muted-foreground`) so the actual data values stand out.
