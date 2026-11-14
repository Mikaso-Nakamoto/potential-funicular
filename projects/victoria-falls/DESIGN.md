---
name: Victoria Falls — design language
description: "Тёмный макроэкономический терминал: базальта-канвас, туманные поверхности, единственный холодный акцент «водопадной взвеси» (oklch 192°), дисплейный серифный логотип против монопространственных табличных цифр. Плотность и hairline-границы взяты у linear.app, работа с числами и ролями цвета — у stripe, геометрия поверхностей — у mercury. Никаких indigo/purple-градиентов, никаких плоских теней и transition-all."
version: alpha
source_skills:
  - agent-skills/design-logic/design-md-library
  - agent-skills/ui/antislop
  - agent-skills/ui/taste-skill
  - agent-skills/web-platform/modern-web-guidance

colors:
  canvas: "oklch(0.168 0.012 250)"
  canvas-deep: "oklch(0.135 0.012 252)"
  surface-1: "oklch(0.212 0.014 250)"
  surface-2: "oklch(0.248 0.016 250)"
  surface-3: "oklch(0.288 0.018 250)"
  surface-glass: "oklch(0.24 0.016 250 / 0.72)"
  ink: "oklch(0.975 0.004 250)"
  ink-muted: "oklch(0.86 0.01 250)"
  ink-subtle: "oklch(0.72 0.012 250)"
  ink-tertiary: "oklch(0.58 0.014 250)"
  hairline: "oklch(0.36 0.016 250 / 0.55)"
  hairline-strong: "oklch(0.44 0.02 250 / 0.7)"
  accent: "oklch(0.8 0.125 192)"
  accent-hover: "oklch(0.87 0.115 192)"
  accent-press: "oklch(0.72 0.13 194)"
  accent-soft: "oklch(0.8 0.125 192 / 0.14)"
  on-accent: "oklch(0.22 0.04 215)"
  gold: "oklch(0.85 0.135 85)"
  up: "oklch(0.79 0.155 155)"
  down: "oklch(0.7 0.185 22)"
  neutral: "oklch(0.64 0.012 250)"

typography:
  display:
    fontFamily: "Iowan Old Style, Palatino Linotype, Georgia, ui-serif"
    fontSize: "clamp(2rem, 1.1rem + 3.4vw, 4.25rem)"
    fontWeight: 400
    lineHeight: 1.02
    letterSpacing: "-0.025em"
  heading:
    fontFamily: "system-ui, -apple-system, Segoe UI, Roboto"
    fontSize: "clamp(1.375rem, 1.1rem + 0.9vw, 1.75rem)"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.015em"
  body:
    fontFamily: "system-ui, -apple-system, Segoe UI, Roboto"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "-0.005em"
  data:
    fontFamily: "ui-monospace, SF Mono, JetBrains Mono, Menlo"
    fontSize: 14px
    fontWeight: 500
    fontVariantNumeric: tabular-nums
    fontFeatureSettings: "tnum 1, zero 1"
  eyebrow:
    fontFamily: "system-ui"
    fontSize: 11px
    fontWeight: 600
    letterSpacing: "0.09em"
    textTransform: uppercase

rounded:
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  xxl: 22px
  pill: 9999px

spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px

shadows:
  raised: "0 1px 1px oklch(0 0 0 / 0.35), 0 2px 8px oklch(0 0 0 / 0.28)"
  panel: "0 1px 1px oklch(0 0 0 / 0.4), 0 8px 24px oklch(0 0 0 / 0.38), inset 0 1px 0 oklch(1 0 0 / 0.045)"
  overlay: "0 2px 4px oklch(0 0 0 / 0.45), 0 24px 60px oklch(0 0 0 / 0.5), inset 0 1px 0 oklch(1 0 0 / 0.06)"

motion:
  ease-out: "cubic-bezier(0.16, 1, 0.3, 1)"
  ease-spring: "cubic-bezier(0.34, 1.56, 0.64, 1)"
  duration-fast: 120ms
  duration-base: 220ms
  duration-slow: 380ms

---

# Victoria Falls — правила дизайна

## Что это за система

Это **гибрид**, собранный по методике `design-md-library`: у каждого источника взята одна сильная черта, а не весь стиль целиком.

| Источник | Что взяли | Что НЕ взяли |
| --- | --- | --- |
| `linear.app` | шкалу поверхностей от `canvas` до `surface-3`, hairline-границы, плотность строк, pill-радиусы кнопок | их lavender-акцент (`#5e6ad2`) |
| `stripe` | табличные цифры, отрицательный трекинг на крупных числах, роли цвета (`primary`, `ink-mute`, `hairline`) | светлую тему и их proprietary Sohne |
| `mercury` | спокойные крупные радиусы панелей, тихие тени | их банковскую пастель |
| собственное | акцент «водопадной взвеси» — холодный аква `oklch(0.8 0.125 192)`, дисплейный серифный логотип | — |

## Цвет

- **60–30–10.** 60% — `canvas`/`canvas-deep`, 30% — поверхности и hairline, 10% — акцент.
- Акцент используется **только** на: фокусе, активной вкладке/строке, главной кнопке сохранения и слове «Falls» в логотипе. Он не красит фон, не заливает карточки и не образует градиентов.
- Семантика рынка: `--vf-up` (155°), `--vf-down` (22°), `--vf-neutral`. Никогда не передаём рост/падение только цветом — рядом всегда есть стрелка `↑`/`↓` и знак.
- Чистого `#000` и `#fff` нет: канвас — почти чёрный с синим подтоном, текст — почти белый.

## Типографика

- **Дисплей** (логотип, `VICTORIA FALLS` в подвале) — серифный стек с курсивным акцентом. Это единственное «редакционное» место: оно даёт характер, которого нет у типового дашборда.
- **UI** — системный гротеск, вес 400/500/600, трекинг `-0.005em`. Никакого Inter-по-умолчанию в качестве «дизайна».
- **Данные** — моноширинный стек + `tabular-nums` + `font-feature-settings: "tnum" 1, "zero" 1`. Это обязательное правило: без табличных цифр курсы «прыгают» при обновлении каждые 30 минут.
- Заголовки секций — 11px, uppercase, `letter-spacing: 0.09em` (eyebrow). Они не конкурируют с числами.

## Глубина

- Три z-слоя: `canvas` → `surface-1` (панель) → `surface-2/3` (карточка внутри панели, элементы управления).
- Тени многослойные и с внутренним светом (`inset 0 1px 0 oklch(1 0 0 / .045)`), чтобы панель «лежала» на канвасе, а не висела.
- Плоского `shadow-md` нет. Границы — полупрозрачные hairline, не сплошной серый.

## Раскладка

- Сетка: `288px | 1fr | 288px`, ширина оболочки до 1720px, на 1180px правая колонка уходит вниз, ниже 900px — всё в один столбец.
- `container-type: inline-size` на `.Main-Content`, `.app-header` и конвертере: блоки перестраиваются по **своей** ширине, а не по вьюпорту.
- Мини-графики — `repeat(auto-fit, minmax(...))`, а не жёсткие 5 колонок.

## Движение

- Анимируются только `transform` и `opacity`. `transition-all` запрещён.
- Длительности: 120 мс (отклик на наведение), 220 мс (состояния), 380 мс (появление панелей).
- Появление панелей — `vf-rise-in` со stagger 40 мс. Полное уважение к `prefers-reduced-motion` (включая остановку бегущих строк).
- Бегущие строки останавливаются на hover и на фокусе.

## Состояния

У каждого интерактивного элемента: `hover`, `active` (сдвиг/масштаб 0.94–0.99), `:focus-visible` (двойное кольцо: канвас + акцент). Скрытых интерактивных элементов без доступного имени нет.

## Данные и честность

- Если внешний API недоступен — включается демо-режим: плашка «Демо-данные» в правом нижнем углу + правдоподобные синтетические значения. Пустого экрана не бывает.
- Пока данные грузятся, в блоке стоит `…`, а не `0` и не `undefined`.
- В подвале прямо сказано, что сайт не является инвестиционной рекомендацией.
