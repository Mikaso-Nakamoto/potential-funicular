# Design Logic — дизайн-ДНК, UX-законы, архитектура сайта и конверсия

Категория про **логику**: почему интерфейс устроен именно так, что предусмотреть в сценарии, как измерить результат. Здесь нет «стилей» — здесь числовые дизайн-токены реальных брендов, проверяемые правила качества, эвристики юзабилити и механика конверсии.

**15 навыков** + библиотека из **84 файлов `DESIGN.md`**.

## Каталог

- **[`design-md-library`](design-md-library/SKILL.md)** — 84 разобранные дизайн-системы реальных брендов (Stripe, Linear, Vercel, Apple, Figma, Notion, Shopify, Supabase, Ferrari, Nike…) в формате `DESIGN.md` от Google Stitch: токены цвета по ролям, типографика с точным трекингом и `font-feature`, отступы, радиусы, слои теней. Каталог — [`BRANDS.md`](design-md-library/BRANDS.md).
- **[`design-extract`](design-extract/SKILL.md)** — Реверс-инжиниринг дизайн-языка **любого сайта** через `npx designlang <url>`: markdown для агента, HTML-превью, Tailwind-конфиг, React/shadcn-темы, переменные Figma, W3C-токены, CSS-переменные + WCAG-скоринг.
- **[`laws-of-ux`](laws-of-ux/SKILL.md)** — Все 30 законов UX (Хик, Фиттс, Миллер, Якоб, Теслер, пиковый конец…) как активный советник по вёрстке: рекомендует закон и конкретную правку в коде, плюс режимы `review` (оценка 0–60) и `checklist`.
- **[`information-architecture`](information-architecture/SKILL.md)** — Навигация, таксономия, иерархия, поиск и подписи: «если пользователь не может найти — этого не существует».
- **[`design-heuristics`](design-heuristics/SKILL.md)** — 10 эвристик Нильсена и золотые правила Шнейдермана с оценкой серьёзности: ловят реальные проблемы, а не создают busywork.
- **[`usability-testing`](usability-testing/SKILL.md)** — Методология юзабилити-тестов: дизайн исследования, задачи, модерация, анализ и отчёт. Пять пользователей и один день — достаточно.
- **[`ux-metrics`](ux-metrics/SKILL.md)** — Измерение UX, связанное с бизнес-результатом: HEART, GSM, SUS, task success. Отсекает vanity-метрики.
- **[`interaction-patterns`](interaction-patterns/SKILL.md)** — Когда модалка, а когда drawer, progressive disclosure, inline-редактирование, мобильные жесты и поведение компонентов. «Скучное решение выигрывает».
- **[`site-architecture`](site-architecture/SKILL.md)** — Планирование и реструктуризация сайта: иерархия страниц, навигация, URL-структура, внутренняя перелинковка, миграции.
- **[`cro`](cro/SKILL.md)** — Конверсионная оптимизация: почему страница не конвертирует, что менять первым, какие поля и блоки убрать. Лендинги, прайсинг, формы.
- **[`onboarding`](onboarding/SKILL.md)** — Первая сессия и активация: aha-момент, чек-листы, пустые состояния, time-to-value.
- **[`pricing`](pricing/SKILL.md)** — Ценообразование и упаковка: тарифы, метрики ценности, per-seat vs usage, freemium и триалы, страницы тарифов.
- **[`copywriting`](copywriting/SKILL.md)** — Тексты страниц: какой заголовок и обещание вести первым, диагностика входа (пустой бриф / живой голос / точечная правка), доказуемость утверждений.
- **[`copy-editing`](copy-editing/SKILL.md)** — Редактура готового текста: убирает маркеры ИИ-письма («это не X, это Y», «ни X, ни Y, ни Z», хвосты-уточнения), не переписывая с нуля.
- **[`numerique-responsable`](numerique-responsable/SKILL.md)** — Правила качества и сценариев из RGESN, GR491, Opquast (245 правил) и RGAA: настоящий 404, закрытие аккаунта, отписка без подтверждения, вес страницы, семантика.

## Как этим пользоваться в связке

1. **Определи структуру и сценарии:** `site-architecture` → `information-architecture` → `numerique-responsable` (проверка «всё ли предусмотрено»).
2. **Задай визуальный язык числами:** `design-md-library` (взять 2–3 бренда) или `design-extract` (снять токены с референса).
3. **Собери и проверь по законам:** `interaction-patterns` → `laws-of-ux` → `design-heuristics`.
4. **Заостри тексты и воронку:** `copywriting` / `copy-editing` → `cro` → `onboarding` / `pricing`.
5. **Измерь:** `ux-metrics` и `agent-skills/web-quality/` (Lighthouse, Core Web Vitals).

## Лицензии и атрибуция

- `design-md-library` — MIT, [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md).
- `design-extract` — MIT, [Manavarya09/design-extract](https://github.com/Manavarya09/design-extract).
- `laws-of-ux` — MIT, [keysjoao/laws-of-ux-skills](https://github.com/keysjoao/laws-of-ux-skills).
- `information-architecture`, `design-heuristics`, `usability-testing`, `ux-metrics`, `interaction-patterns` — MIT, [trevorgrogers/ux-designer-skills](https://github.com/trevorgrogers/ux-designer-skills) (см. [`NOTICE-ux-designer-skills.md`](NOTICE-ux-designer-skills.md)).
- `site-architecture`, `cro`, `copywriting`, `copy-editing`, `pricing`, `onboarding` — MIT, [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills).
- `numerique-responsable` — **CC BY-SA 4.0**, [Institut du Numérique Responsable / skill-nr](https://github.com/Institut-du-Numerique-Responsable/skill-nr). Opquast © Opquast, RGESN © DINUM, GR491 © ISIT.
