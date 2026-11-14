---
name: apple-hig-design
description: Design and implement applications following Apple Human Interface Guidelines (HIG). Covers iOS/macOS aesthetic principles, vibrancy materials, blur effects, continuous rounded corners (squircles), SF Pro typography, dynamic type, tactile feedback, and intuitive gestures.
---

# Apple Human Interface Guidelines (HIG) Skill

This skill guides agents in designing and implementing software that follows the clarity, deference, and depth principles of Apple's Human Interface Guidelines.

## Core Tenets

1. **Clarity:** Text is legible at every size, icons are precise and lucid, adornments are subtle, and functionality drives design.
2. **Deference:** Fluid motion and a crisp interface help people understand and interact with content without competing with it. Content fills the screen while transclucency and materials hint at more.
3. **Depth:** Visual layers and realistic motion impart vitality and heighten understanding of hierarchy.

---

## 1. Materials & Vibrancy (Translucency)

Apple UIs use translucent materials to create a sense of depth, allowing the user's wallpaper and underlying content to shine through subtly:

### Tailwind / CSS Equivalents:
- **Ultra-thin Material (Navbars, Sheets):**
  `bg-white/70 dark:bg-black/70 backdrop-blur-xl backdrop-saturate-150 border-b border-black/5 dark:border-white/10`
- **Thick Material (Floating Control Bars, Floating Docks):**
  `bg-neutral-100/80 dark:bg-neutral-900/80 backdrop-blur-2xl shadow-lg border border-black/5 dark:border-white/10`

---

## 2. Corner Radius & Continuous Curves (Squircles)

Apple devices and software never use circular arcs for rounded corners; they use **continuous curvature** (superellipses / squircles), which blend seamlessly into straight edges:

- On iOS/macOS web: Use `rounded-[22px]` for standard cards, `rounded-[14px]` for buttons, `rounded-[10px]` for small controls.
- When supported, apply `corner-smoothing: 60%` (or CSS Houdini squircle paints).

---

## 3. Typography & System Fonts

- **Font Family:** Prioritize Apple's system font cascade:
  ```css
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
  ```
- **SF Pro Display:** Use for sizes >= 20pt (`text-xl` and above) with tighter letter spacing (`tracking-tight`).
- **SF Pro Text:** Use for sizes < 20pt with neutral or slightly expanded tracking for legibility.

---

## 4. Touch Targets & Ergonomics

- **Minimum Tap Target:** Every interactive element must have a minimum clickable area of **44x44pt** (even if the visible icon is only 20px). Use padding or invisible hit slops (`before:absolute before:-inset-2`).
- **Thumb Zone Navigation:** Primary actions and tab bars live at the bottom of the screen (`fixed bottom-0 pb-safe`), while search and status live at the top.

---

## 5. Micro-Interactions & Haptic Physics

- **Button Press:** Immediate, spring-loaded scale feedback on active state:
  `active:scale-[0.96] transition-transform duration-150 ease-out`
- **Spring Curves:** Never use linear or abrupt easing. Use Apple-like spring cubic beziers:
  `cubic-bezier(0.25, 1, 0.5, 1)` or spring physics with slight bounce on interactive dismissals.
