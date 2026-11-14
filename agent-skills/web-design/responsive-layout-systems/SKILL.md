---
name: responsive-layout-systems
description: Build modern responsive, intrinsic web layouts using CSS Container Queries (@container), CSS Subgrid, fluid clamp() typography, and auto-fit flex/grid patterns. Prevents fragile breakpoint-heavy media query code.
---

# Responsive Layout Systems Skill

This skill guides agents in building fluid, intrinsic responsive layouts that adapt automatically to container constraints, eliminating brittle media-query spaghetti.

## 1. Intrinsic Sizing Over Rigid Breakpoints

Instead of writing separate classes for `sm:`, `md:`, `lg:`, `xl:`, and `2xl:` on every element, use CSS grid `auto-fit` with `minmax()`:

```html
<!-- Automatically wraps from 1 to 4 columns based on available space -->
<div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,280px),1fr))] gap-6">
  <div class="card">...</div>
  <div class="card">...</div>
  <div class="card">...</div>
</div>
```

---

## 2. Container Queries (`@container`)

Components should adapt to their **parent container**, not the global browser viewport. A card in a narrow sidebar should render differently from the same card in a wide main feed:

```html
<!-- Parent defines the container context -->
<div class="@container">
  <!-- Child adapts based on container width (@sm: 384px, @md: 448px, @lg: 512px) -->
  <article class="flex flex-col @md:flex-row items-start @md:items-center gap-4 p-6 bg-card rounded-xl">
    <img class="w-full @md:w-32 h-32 object-cover rounded-lg" src="..." alt="..." />
    <div>
      <h3 class="text-base @md:text-xl font-bold">Title</h3>
      <p class="text-sm text-muted-foreground">Description...</p>
    </div>
  </article>
</div>
```

---

## 3. Fluid Typography with `clamp()`

Never let headlines blow up on mobile or look tiny on ultra-wide screens. Use mathematical fluid clamping:

```css
/* Scales smoothly from 28px at 375px viewport to 56px at 1440px viewport */
font-size: clamp(1.75rem, 1rem + 2.5vw, 3.5rem);
line-height: 1.1;

/* Fluid padding/margins that breathe with the viewport */
padding-inline: clamp(1rem, 5vw, 4rem);
```

---

## 4. Aligning Nested Items with CSS Subgrid

Solve the classic problem of card footers or titles being misaligned across grid columns:

```html
<div class="grid grid-cols-3 gap-6">
  <!-- Card spans rows and inherits row tracks from parent -->
  <div class="grid grid-rows-subgrid row-span-3 p-6 bg-card rounded-xl">
    <h3 class="text-lg font-bold">Variable Title Height</h3>
    <p class="text-muted-foreground">Variable body text length that normally throws off button alignment...</p>
    <button class="mt-auto bg-primary text-white py-2 rounded">Always Aligned Button</button>
  </div>
</div>
```
