# Claude Code & AI Agents — Repo Guide

Этот репозиторий содержит единую библиотеку из **243 навыков (Agent Skills)** для создания выразительных сайтов, дизайн-систем, микро-анимаций, нативных возможностей современной веб-платформы, 3D/WebGL сцен, браузерных игр и защищённых приложений.

## Рекомендуемый пайплайн для фронтенда и веб-дизайна

Перед написанием любого UI/HTML/CSS/React-кода **всегда** загружай профильные навыки из `agent-skills/`:

0. **Современная веб-платформа без устаревших JS-костылей (Chrome / Edge / Firefox / MDN):**
   - `agent-skills/web-platform/modern-web-guidance/SKILL.md` (и локальные гайды в `agent-skills/web-platform/modern-web-guidance/guides/`) — нативные `<dialog>`, Popover API, CSS Anchor Positioning, `oklch()`, `subgrid`, `@starting-style`, View Transitions, оптимизация INP.
1. **Выбор направления и защита от стокового ИИ-стиля (обязательно на старте):**
   - Лендинги, промо-сайты, портфолио: `agent-skills/ui/taste-skill/SKILL.md` + `agent-skills/ui/no-ai-design-slop/SKILL.md`
   - Продуктовый UI и веб-приложения: `agent-skills/ui/frontend-design/SKILL.md` или `agent-skills/ui/anthropic-frontend-design/SKILL.md`
   - Автоподбор палитры, шрифтов и паттернов под индустрию: `agent-skills/ui/ui-ux-pro-max/SKILL.md`
2. **Конкретная визуальная тема или эффект:**
   - Выбери подходящий стиль в `agent-skills/web-design/` (94 навыка: темы, шейдеры, скролл-сцены, Three.js, GSAP + Lenis) или `agent-skills/3d/` / `agent-skills/illustration/`.
3. **Тактильность и микро-анимации уровня Linear / Apple:**
   - Подключи нужный навык из `agent-skills/design-engineering/` (`emil-design-eng`, `animate`, `choreograph`, `gestures`, `animation-performance`).
4. **Финальная критика, полировка и аудит перед сдачей:**
   - Визуальная полировка: `agent-skills/ui/impeccable/SKILL.md` и `agent-skills/ui/audit-ai-design-slop/SKILL.md`
   - Доступность, UX и производительность React/Next.js: `agent-skills/vercel/web-design-guidelines/SKILL.md` и `agent-skills/vercel/react-best-practices/SKILL.md`

---

## Anti-Generic Guardrails (жёсткие запреты против «пластикового» ИИ-дизайна)

- **Шрифты:** никогда не используй один дефолтный `Inter` / `Roboto` / `Arial` одновременно для заголовков и текста. Подбирай характерную пару (выразительный display/serif для заголовков + чистый гротеск/моноширинный для текста и метаданных). На крупных заголовках держи плотный трекинг (`-0.02em`..`-0.04em`) и интерлиньяж `1.05–1.15`.
- **Цвета:** не используй дефолтные `indigo-500` / `blue-600` и фиолетово-синие градиенты на белом фоне. Строй палитру по правилу **60–30–10** с одним осмысленным акцентным цветом. Избегай чистого `#000000` на `#FFFFFF`.
- **Глубина и тени:** не используй плоский `shadow-md`. Применяй многослойные физически точные тени (`agent-skills/web-design/beautiful-shadows/SKILL.md`), тонкие полупрозрачные границы и разделение z-слоёв (base → surface → elevated → floating).
- **Сетка и композиция:** избегай шаблонных 3 одинаковых карточек с иконками в кружочках по центру. Используй асимметричный ритм, модульные сетки и достаточный воздух между секциями.
- **Анимации:** никогда не пиши `transition-all`. Анимируй только `transform` и `opacity` с выверенными кривыми (`cubic-bezier` / spring) и поддержкой `prefers-reduced-motion`.
- **Интерактивные состояния:** у каждого кликабельного элемента обязаны быть состояния `hover`, `active` и заметный `focus-visible`.

---

## Контракт папки навыка

```text
agent-skills/<category>/<skill-name>/
  SKILL.md            # обязательный манифест и пошаговая процедура
  REFERENCES.md       # опционально: ссылки на документацию
  references/         # опционально: детальные справочники и правила
  assets/             # опционально: шаблоны, компоненты, токены
  scripts/            # опционально: утилиты поиска и валидации
  demo/               # опционально: автономное HTML-демо и промпт
```
