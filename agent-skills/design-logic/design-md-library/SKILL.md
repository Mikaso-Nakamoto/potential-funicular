---
name: design-md-library
description: >
  Библиотека из 84 готовых DESIGN.md — разобранных дизайн-систем реальных брендов (Stripe, Linear, Vercel, Apple, Figma, Notion, Shopify, Supabase, Ferrari, Nike…).
  Используй, когда нужен точный визуальный язык вместо абстрактного «сделай красиво»: подобрать дизайн-ДНК под нишу,
  собрать гибрид из 2–3 систем, задать токены проекта (цвет, типографика с трекингом, отступы, радиусы, тени) или
  удержать консистентность между страницами. Триггеры: DESIGN.md, дизайн-система, токены, «как у Stripe/Linear/Vercel»,
  «в стиле такого-то бренда», стайлгайд, палитра и типографика проекта.
license: MIT (файлы DESIGN.md — анализ дизайн-систем, © VoltAgent, MIT)
---

# Design MD Library — 84 дизайн-ДНК реальных брендов

## Что это

`DESIGN.md` — концепция **Google Stitch**: обычный markdown-файл в корне проекта, который читает дизайн-агент.

| Файл | Кто читает | Что задаёт |
| --- | --- | --- |
| `AGENTS.md` | Кодовый агент | **как строить** проект (архитектура, стек, команды) |
| `DESIGN.md` | Дизайн-агент | **как проект должен выглядеть и ощущаться** |

В отличие от «опиши стиль словами», `DESIGN.md` даёт **числа**: `fontSize: 56px`, `fontWeight: 300`, `lineHeight: 1.03`, `letterSpacing: -1.4px`, `fontFeature: ss01`, точные hex-токены ролей (`primary`, `ink-mute`, `hairline`, `canvas-soft`), отступы, радиусы, слои теней и правила композиции. Именно поэтому он побеждает обычные промпты: агенту не нужно догадываться о масштабе.

## Каталог

Полный список всех 84 систем с описаниями: **[`BRANDS.md`](BRANDS.md)** (таблица «бренд → файл → о чём система»).

Файлы: [`brands/<бренд>/DESIGN.md`](brands/) — по одному на бренд.

Кластеры, по которым удобно искать:

- **B2B SaaS и инфраструктура:** `stripe`, `linear.app`, `vercel`, `supabase`, `resend`, `posthog`, `sentry`, `sanity`, `clickhouse`, `hashicorp`, `mongodb`, `sap`, `oracle`, `ibm`, `hp`, `airtable`, `notion`, `miro`, `intercom`, `mintlify`, `warp`, `raycast`, `replicate`, `together.ai`, `ollama`, `cohere`, `mistral.ai`, `expo`, `lovable`, `clay`, `composio`, `jobright`, `cal`, `zapier`, `webflow`, `slack`
- **Финтех и крипта:** `coinbase`, `binance`, `kraken`, `revolut`, `wise`, `mastercard`, `mercury`, `nerdwallet`
- **Авто, аэро и премиум:** `ferrari`, `lamborghini`, `bmw`, `bmw-m`, `bugatti`, `renault`, `tesla`, `spacex`, `dji`, `nvidia`
- **E-commerce и потребительские бренды:** `shopify`, `nike`, `starbucks`, `airbnb`, `uber`, `spotify`, `oura`, `mydealz`, `1win`
- **Медиа и контент:** `theverge`, `wired`, `aljazeera`, `pinterest`
- **Геймдев и развлечения:** `playstation`, `nintendo-2001`, `dell-1996` (ретро-стилистика 90-х)
- **AI и дизайн-инструменты:** `claude`, `cursor`, `figma`, `framer`, `minimax`, `elevenlabs`, `runwayml`, `opencode.ai`, `voltagent`, `meta`, `x.ai`, `apple`, `superhuman`

## Процесс

1. **Определи нишу и темперамент.** B2B-инструмент → `linear.app` / `vercel` / `stripe`. Потребительский продукт → `apple` / `spotify` / `pinterest`. Премиум-физический продукт → `ferrari` / `bmw-m` / `bugatti`. Медиа → `theverge` / `aljazeera`. Игра → `playstation` / `nintendo-2001`.
2. **Прочитай 2–3 файла целиком.** Открой `brands/<бренд>/DESIGN.md` — там YAML-токены + текстовые правила (композиция, состояния, motion, чего избегать).
3. **Собери гибрид, а не копию.** Возьми: цветовую роль-модель у одного бренда, типошкалу и трекинг у второго, геометрию поверхностей (радиусы/тени/границы) у третьего. Прямое копирование бренда — риск для айдентики и юридика; перенос **структуры решения** — нет.
4. **Зафиксируй результат в `DESIGN.md` проекта.** Создай свой файл с выбранными токенами + правилами. Дальше все страницы ссылаются на него, а не изобретают палитру заново.
5. **Сверься с анти-слоп-правилами.** Прогони итог через `agent-skills/ui/antislop/SKILL.md` и `agent-skills/ui/no-ai-design-slop/SKILL.md`.

## Как переносить токены

- **Цвет:** переноси **роли**, а не только hex: `primary`, `primary-press`, `ink`, `ink-mute`, `canvas`, `canvas-soft`, `hairline`. В CSS — `:root` с семантическими переменными, не сырыми именами бренда.
- **Типографика:** копируй тройку `fontSize / weight / letterSpacing` целиком. Дисплейные заголовки у Strong-систем идут **лёгким** весом (300) с отрицательным трекингом — это ключ к «дорогому» виду.
- **Геометрия:** радиусы кратны базовой единице (обычно 4 / 6 / 8 / 12 / 9999), тени — многослойные с цветным подмешиванием (`shadow-blue` у Stripe), границы — `hairline` полупрозрачные.
- **Никогда** не переноси proprietary-шрифты (Sohne, SF Pro, GT America) как файлы — подставляй свободные аналоги и указывай fallback-стек из файла.

## Связки

- Нужны живые токены из **чужого сайта** → `agent-skills/design-logic/design-extract/SKILL.md` (`npx designlang <url>`).
- Нужно сперва выбрать арт-направление → `agent-skills/ui/taste-skill/SKILL.md` или `agent-skills/ui/ui-ux-pro-max/SKILL.md`.
- Нужна проверка «не выглядит ли как ИИ» → `agent-skills/ui/antislop/SKILL.md`, `agent-skills/ui/audit-ai-design-slop/SKILL.md`.
- Нужны актуальные браузерные приёмы для реализации → `agent-skills/web-platform/modern-web-guidance/SKILL.md`.

## Атрибуция

Файлы `brands/*/DESIGN.md` взяты из [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md) (MIT). Это независимый анализ публичных дизайн-систем, а не официальные гайдлайны брендов; названия и логотипы принадлежат их владельцам.
