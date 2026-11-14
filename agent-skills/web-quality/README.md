# Web Quality — производительность, доступность и SEO

**6 навыков** по Lighthouse и Core Web Vitals от Эдди Османи (Addy Osmani, Google Chrome). Отвечают на вопрос «сайт красивый — а он вообще работает быстро, доступно и находится в поиске?».

## Каталог

- **[`web-quality-audit`](web-quality-audit/SKILL.md)** — Сводный аудит качества: собирает все измерения Lighthouse в один отчёт с приоритезированным планом исправлений. Начинай с него.
- **[`core-web-vitals`](core-web-vitals/SKILL.md)** — Пороги и причины трёх метрик: **LCP** (скорость главного контента), **INP** (отзывчивость на действие), **CLS** (визуальная стабильность) — что именно чинить для каждого.
- **[`performance`](performance/SKILL.md)** — Загрузка, критический путь, изображения и шрифты, кеширование, разбиение бандла, работа главного потока.
- **[`accessibility`](accessibility/SKILL.md)** — Доступность по Lighthouse: контраст, доступные имена, роли и ARIA, клавиатурная навигация, скринридеры.
- **[`seo`](seo/SKILL.md)** — Техническое SEO: заголовки и метаданные, структура URL, индексируемость, канонические ссылки, Core Web Vitals как фактор.
- **[`best-practices`](best-practices/SKILL.md)** — Гигиена веба: HTTPS, консольные ошибки, устаревшие API, безопасность сторонних скриптов, корректность изображений.

## Как встроить в работу

1. **Перед сдачей проекта:** `web-quality-audit` → чек-лист с приоритетами.
2. **По каждой проблеме:** соответствующий навык (`performance` / `accessibility` / `seo` / `best-practices`).
3. **Метрики LCP/INP/CLS:** `core-web-vitals` — там пороги «хорошо / надо улучшить / плохо».
4. **Современные нативные решения вместо библиотек:** `agent-skills/web-platform/modern-web-guidance/SKILL.md`.

## Связки

- Логика сценариев и требований к качеству: `agent-skills/design-logic/numerique-responsable/SKILL.md`.
- Визуальная полировка без потери производительности: `agent-skills/ui/impeccable/SKILL.md`, `agent-skills/design-engineering/animation-performance/SKILL.md`.
- React/Next.js-специфика: `agent-skills/vercel/react-best-practices/SKILL.md`.

## Атрибуция

[addyosmani/web-quality-skills](https://github.com/addyosmani/web-quality-skills), лицензия MIT. Часть правил опирается на материалы [web-interface-guidelines](https://github.com/vercel-labs/web-interface-guidelines) (см. `LICENSE-web-quality-skills` внутри `ui/antislop-ui/`).
