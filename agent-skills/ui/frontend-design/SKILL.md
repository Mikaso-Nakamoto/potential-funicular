---
name: frontend-design
description: Create distinctive, human-crafted, production-ready frontend web designs. Prevents generic "AI look" (Inter/Roboto default, generic purple/blue gradients, centered boring cards). Use when designing or building landing pages, web applications, dashboards, or UI components where visual taste, memorable typography, cohesive color theory, and refined spatial rhythm are required.
---

# Frontend Design Skill

This skill guides agents to build distinctive, memorable, human-level frontend interfaces that stand out from generic AI-generated boilerplates.

## Core Directive: Eliminate the "Generic AI Aesthetic"

Default AI frontend code suffers from predictable clichés:
- Font: Inter or Roboto everywhere
- Colors: White background, gray borders (`border-gray-200`), generic indigo/blue buttons (`bg-indigo-600`)
- Layout: Centered text, 3-column feature cards with colorful rounded icon boxes
- Spacing: Inconsistent padding, no vertical rhythm
- Atmosphere: Flat or covered in random pastel blur blobs

**Do not produce these clichés.** Every design must have an intentional, authored creative direction.

---

## 1. Typography Pairing & Character

Typography dictates 80% of an interface's personality.

### Rules:
1. **Choose an opinionated display typeface for headings:**
   - *High-Tech / Future:* Syne, Space Grotesk, Clash Display, Cabinet Grotesk
   - *Clean Modern Luxury:* Plus Jakarta Sans, General Sans, Satoshi
   - *Editorial / High-Trust / FinTech:* Newsreader, Playfair Display, Fraunces, EB Garamond
   - *Developer / Technical:* JetBrains Mono, Fragment Mono, Geist Mono
2. **Pair with a legible neutral body typeface:**
   - E.g., Geist, Inter (body only), Outfit, Archivo, or system fonts (`system-ui`).
3. **Contrast Sizes & Weights:**
   - Dramatic scale: Display headers should feel monumental (`text-5xl` to `text-7xl`), while micro-labels, badges, and metadata should be crisp, uppercase, and tracked out (`text-xs uppercase tracking-wider font-mono`).
4. **Leading (Line-height) Control:**
   - Large display headlines MUST use tight line height (`leading-[1.05]` to `leading-[1.15]`).
   - Body copy MUST breathe (`leading-relaxed` or `leading-7`).

---

## 2. Color Theory: The 60-30-10 Rule

A focused palette always looks more professional than random splashes of color.

- **60% Dominant Base:** The background canvas and dominant surfaces (e.g., warm cream `#FDFBF7`, deep obsidian `#0A0A0C`, or slate zinc `#090D16`).
- **30% Structural Secondary:** Cards, navigation rails, borders, secondary text, and muted fills that define the geometry.
- **10% Intentional Accent:** Exactly ONE primary brand accent color (e.g., electric lime `#D4FF00`, safety orange `#FF5500`, cobalt blue `#1D4ED8`, or jade `#10B981`) reserved exclusively for primary CTAs, active indicators, and high-value focus points.

### Semantic Contrast:
- Never use pure black (`#000000`) on pure white (`#FFFFFF`) for large text blocks; use deep charcoal or slate (`#111827`, `#0F172A`) for reduced eye strain and higher elegance.
- In dark mode, avoid pure black for containers; layer tonal surfaces (`bg-[#121214]` on `bg-[#0A0A0C]`).

---

## 3. Spatial Rhythm & Layout Architecture

- **Generous Negative Space (Whitespace):** Premium designs give elements room to breathe. Do not crowd elements. Use `py-24` to `py-32` between major landing page sections.
- **Asymmetric Balance:** Break away from identical 3-card rows. Use hero bento-layouts with varying proportions (e.g., 2/3 + 1/3 splits, horizontal showcase banners, sticky side-by-side walkthroughs).
- **Whitespace Over Borders:** Group related items through proximity and background tone before reaching for border lines.

---

## 4. Tactile Micro-Interactions & Depth

- **Refined Borders & Glass:** In dark themes, use semi-transparent white borders (`border-white/10` or `border-white/5`) instead of solid gray lines.
- **Physical Elevation:** Use multi-stop layered drop shadows (ambient occlusion) rather than single harsh CSS shadows.
- **Interactive Feedback:** Every clickable element must have distinct, authored states:
  - `hover`: subtle translateY (`-translate-y-0.5`), scale or brightness shift.
  - `active`: press feedback (`translate-y-0` or `scale-[0.98]`).
  - `focus-visible`: clear, accessible keyboard focus ring.

---

## 5. Pre-Delivery Checklist

Before completing frontend code:
1. Did you avoid generic boilerplate fonts and colors?
2. Is the visual hierarchy immediately obvious within 3 seconds?
3. Are interactive buttons and inputs responsive to keyboard (`Tab` + `Enter`) and touch?
4. Does the layout scale gracefully from 375px mobile screens up to 4K displays?
5. Does it look like an experienced human designer built it with purpose?
