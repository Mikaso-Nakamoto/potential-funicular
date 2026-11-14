---
name: framer-motion-system
description: Implement fluid, production-ready animations and micro-interactions in React and Next.js applications using Framer Motion. Covers spring physics, layout animations (layoutId), exit animations (AnimatePresence), scroll-driven animations, gesture controls, and performance optimization.
---

# Framer Motion System Skill

This skill guides agents in building fluid, physics-based animations in React and Next.js using Framer Motion (`framer-motion` or `motion/react`).

## Core Principles

1. **Spring Physics Over Fixed Durations:**
   Real physical objects have mass, stiffness, and damping. Use springs for interactive gestures and UI transitions rather than rigid linear or ease-in-out timers.
2. **GPU Acceleration Only:**
   Animate `transform` (`x`, `y`, `scale`, `rotate`) and `opacity`. Never animate `width`, `height`, `top`, `left`, or `margin` directly (use `layout` prop instead).
3. **Respect Reduced Motion:**
   Always wrap animated components with `useReducedMotion()` to instantly resolve states for users who prefer minimal movement.

---

## 1. Spring Presets & Animation Standards

```tsx
// Reusable Spring Configs
export const springs = {
  // Snappy for buttons, toggles, small controls
  snappy: { type: "spring", stiffness: 500, damping: 30 },
  // Smooth for dialogs, drawers, cards
  smooth: { type: "spring", stiffness: 300, damping: 25 },
  // Bouncy for success badges, celebration moments
  bouncy: { type: "spring", stiffness: 400, damping: 15, mass: 1 },
}
```

---

## 2. Shared Element Transitions (`layoutId`)

Use `layoutId` for tabs, active indicators, and modal expansions:

```tsx
import { motion } from "framer-motion"
import { useState } from "react"

const tabs = ["Overview", "Integrations", "Activity", "Settings"]

export function AnimatedTabs() {
  const [activeTab, setActiveTab] = useState(tabs[0])

  return (
    <div className="flex gap-2 p-1 bg-zinc-900 rounded-xl">
      {tabs.map((tab) => {
        const isActive = activeTab === tab
        return (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className="relative px-4 py-2 text-sm font-medium text-white transition-colors"
          >
            {isActive && (
              <motion.div
                layoutId="active-pill"
                className="absolute inset-0 bg-zinc-800 rounded-lg shadow-sm"
                transition={springs.smooth}
              />
            )}
            <span className="relative z-10">{tab}</span>
          </button>
        )
      })}
    </div>
  )
}
```

---

## 3. Exit Animations with `AnimatePresence`

Ensure unmounting elements animate out smoothly:

```tsx
import { AnimatePresence, motion } from "framer-motion"

export function NotificationBanner({ isVisible, onClose }) {
  return (
    <AnimatePresence mode="wait">
      {isVisible && (
        <motion.div
          initial={{ opacity: 0, y: -12, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -8, scale: 0.96 }}
          transition={springs.snappy}
          className="rounded-lg bg-zinc-900 border border-zinc-800 p-4 text-white"
        >
          Changes saved successfully.
        </motion.div>
      )}
    </AnimatePresence>
  )
}
```

---

## 4. Staggered Container Orchestration

For revealing lists or grid cards:

```tsx
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.1,
    },
  },
}

const itemVariants = {
  hidden: { opacity: 0, y: 16 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { type: "spring", stiffness: 350, damping: 25 },
  },
}
```
