# Agent Skills Vault

Единая библиотека переиспользуемых навыков (**Agent Skills**) в формате Markdown для AI-агентов (**Claude Code**, **Codex**, **Cursor**, **Windsurf**, **Antigravity**, **Lovable**, **v0** и других).

В репозитории собрано **69 уникальных навыков** без дубликатов: от дизайн-систем, шейдеров и веб-анимаций до разработки браузерных 3D-игр на Three.js, модерации Яндекс Игр, автоматизации AI-воркфлоу и прикладной криптографии.

![Галерея превью навыков](SCREENSHOTS-preview.jpg)

---

## Оглавление

1. [Структура репозитория](#структура-репозитория)
2. [Как использовать навыки](#как-использовать-навыки)
3. [Каталог навыков (69)](#каталог-навыков)
   - [UI и дизайн-системы (6)](#1-ui-и-дизайн-системы-agent-skillsui)
   - [Веб-дизайн, анимации и шейдеры (17)](#2-веб-дизайн-анимации-и-шейдеры-agent-skillsweb-design)
   - [Codex и AI-воркфлоу (17)](#3-codex-и-ai-воркфлоу-agent-skillscodex)
   - [Разработка игр / Three.js (19)](#4-разработка-игр--threejs-agent-skillsgame-development)
   - [Безопасность и криптография (6)](#5-безопасность-и-криптография-agent-skillssecurity-crypto)
   - [Медиа и визуальные ассеты (2)](#6-медиа-и-визуальные-ассеты-agent-skillsmedia)
   - [Яндекс Игры (2)](#7-яндекс-игры-agent-skillsya_skills)
4. [Демо и галерея скриншотов](#демо-и-галерея-скриншотов)

---

## Структура репозитория

```text
agent-skills/
  ui/                 # Дизайн-системы, UI-архитектура и промптинг интерфейсов (6)
  web-design/         # Визуальные темы, моушн, WebGL/шейдеры, адаптивная вёрстка (17)
  codex/              # Агентные циклы, захват референсов, аудит, профилирование (17)
  game-development/   # Архитектура браузерных и Three.js игр, ИИ врагов, VFX, QA (19)
  security-crypto/    # Прикладная криптография, управление ключами, защита и фаззинг (6)
  media/              # Подбор стоковых и продуктовых изображений (2)
  YA_SKILLS/          # Аудит модерации и авто-исправления для Яндекс Игр (2)
```

Каждый папочный навык следует единому контракту:
- `SKILL.md` — основная инструкция с YAML-frontmatter (`name`, `description`), правилами, сниппетами и антипаттернами;
- `REFERENCES.md` / `references/` *(опционально)* — документация и референсы;
- `demo/` *(опционально)* — автономное HTML-демо (`index.html`), промпт воссоздания (`PROMPT.md`) и превью (`preview.jpg`);
- `scripts/` и `assets/` *(опционально)* — вспомогательные скрипты и ресурсы.

---

## Как использовать навыки

- **Claude Code:** добавьте ссылку на нужную папку в `CLAUDE.md` (см. [CLAUDE.md](CLAUDE.md)), скопируйте в директорию навыков Claude или передайте `SKILL.md` в контекст задачи.
- **Cursor / Windsurf:** подключите нужный `SKILL.md` через правила проекта (`.cursor/rules` / `.cursorrules`) или прикрепите файл в чат через `@`.
- **Codex / Antigravity:** укажите агенту прочитать соответствующий `SKILL.md` перед выполнением задачи.
- **v0 / Lovable / веб-чаты:** скопируйте содержимое нужного `SKILL.md` в системный промпт или первое сообщение диалога.

---

## Каталог навыков

### 1. UI и дизайн-системы ([`agent-skills/ui/`](agent-skills/ui/README.md))

- **[`apple-hig-design`](agent-skills/ui/apple-hig-design/SKILL.md)** — Apple Human Interface Guidelines: материалы vibrancy/blur, непрерывные скругления (squircle), типографика SF Pro и жесты.
- **[`design-first-ui-prompting`](agent-skills/ui/design-first-ui-prompting/SKILL.md)** — Структурирование UI-промптов в виде чётких дизайн-спецификаций (иерархия, сетка, шрифты, жёсткие ограничения).
- **[`frontend-design`](agent-skills/ui/frontend-design/SKILL.md)** — Авторский фронтенд-дизайн без шаблонного «AI-стиля»: типографические пары, баланс цвета 60-30-10, пространственный ритм.
- **[`google-material-design-3`](agent-skills/ui/google-material-design-3/SKILL.md)** — Официальная дизайн-система Material Design 3 (Material You): динамический цвет HCT, токены и 30+ компонентов (Compose, Flutter, Web).
- **[`refactoring-ui`](agent-skills/ui/refactoring-ui/SKILL.md)** — Практические правила дизайна от разработчиков: визуальная иерархия через вес и контраст, отказ от чистого чёрного, многослойные тени.
- **[`shadcn-ui-design-system`](agent-skills/ui/shadcn-ui-design-system/SKILL.md)** — Архитектура современных веб-приложений на shadcn/ui + Radix UI + Tailwind CSS: CSS-токены, CVA, доступные диалоги и формы.

---

### 2. Веб-дизайн, анимации и шейдеры ([`agent-skills/web-design/`](agent-skills/web-design/README.md))

#### Готовые визуальные темы и арт-дирекшн
- **[`agency-grid-layout-minimal`](agent-skills/web-design/agency-grid-layout-minimal/SKILL.md)** — Минималистичная редакционная сетка агентства с крупной типографикой.
- **[`beautiful-shadows`](agent-skills/web-design/beautiful-shadows/SKILL.md)** — Многослойные реалистичные нейтральные тени Tailwind CSS для карточек и поповеров.
- **[`blue-cloudy-clean-modern`](agent-skills/web-design/blue-cloudy-clean-modern/SKILL.md)** — Светлая воздушная дизайн-система с мягким небесно-синим свечением.
- **[`blue-laser-clean-glass-layout`](agent-skills/web-design/blue-laser-clean-glass-layout/SKILL.md)** — Тёмный стеклянный интерфейс дашбордов с тонкими синими лазерными линиями.
- **[`book-serif-index`](agent-skills/web-design/book-serif-index/SKILL.md)** — Архивно-книжный стиль с антиквой, моноширинным индексом и текстурой бумаги.
- **[`bright-green-tech-system-webgl`](agent-skills/web-design/bright-green-tech-system-webgl/SKILL.md)** — Инженерный тёмный сплит-интерфейс с неоново-зелёным акцентом и WebGL-сценой.
- **[`build-awwwards-quality-sites`](agent-skills/web-design/build-awwwards-quality-sites/SKILL.md)** — Арт-дирекшн и создание сайтов уровня Awwwards (Lenis, режиссура скролла, 3D).

#### Моушн и анимации
- **[`animation-on-scroll`](agent-skills/web-design/animation-on-scroll/SKILL.md)** — Появление элементов при прокрутке через `IntersectionObserver` и Tailwind-анимации.
- **[`animation-systems`](agent-skills/web-design/animation-systems/SKILL.md)** — Продуктовые веб-анимации уровня Stripe, Linear и Apple: тайминги, кривые, переходы.
- **[`cinematic-gsap-lenis-motion-system`](agent-skills/web-design/cinematic-gsap-lenis-motion-system/SKILL.md)** — Кинематографичный веб-моушн на связке GSAP + ScrollTrigger + Lenis.
- **[`framer-motion-system`](agent-skills/web-design/framer-motion-system/SKILL.md)** — Декларативные анимации и микро-интеракции в React/Next.js на Framer Motion.

#### WebGL, шейдеры и эффекты
- **[`add-shader-cursor-trail`](agent-skills/web-design/add-shader-cursor-trail/SKILL.md)** — Мерцающий шейдерный след за курсором на WebGPU/Shaders.
- **[`ambient-section-particles`](agent-skills/web-design/ambient-section-particles/SKILL.md)** — Легковесные интерактивные частицы для фонов отдельных секций.
- **[`atmosphere-background`](agent-skills/web-design/atmosphere-background/SKILL.md)** — Тёмный атмосферный фон с мягкими вертикальными световыми потоками.
- **[`background-grid-webgl`](agent-skills/web-design/background-grid-webgl/SKILL.md)** — Перспективная 3D WebGL-сетка с плавным дрейфом и параллаксом.
- **[`beam-glow-states`](agent-skills/web-design/beam-glow-states/SKILL.md)** — Контурная анимация свечения (`border-beam`) для интерактивных состояний в React.

#### Адаптивная вёрстка
- **[`responsive-layout-systems`](agent-skills/web-design/responsive-layout-systems/SKILL.md)** — Внутренняя адаптивность на CSS Container Queries (`@container`), Subgrid и `clamp()`.

---

### 3. Codex и AI-воркфлоу (`agent-skills/codex/`)

- **[`article-prompts-to-skills`](agent-skills/codex/article-prompts-to-skills/SKILL.md)** — Превращение статей, туториалов и наборов промптов в полноценные автономные навыки с демо и проверкой.
- **[`audit-reference-originality`](agent-skills/codex/audit-reference-originality/SKILL.md)** — Аудит оригинальности дизайна и кода относительно исходных референсов для исключения прямого копирования.
- **[`audit-verify-explain-grade-5`](agent-skills/codex/audit-verify-explain-grade-5/SKILL.md)** — Строгий аудит работы с фактическими доказательствами и простым объяснением результата.
- **[`browser-video-recording`](agent-skills/codex/browser-video-recording/SKILL.md)** — Запись плавных 60 FPS презентационных скринкастов браузера с естественным движением курсора.
- **[`build-daily-inspiration-sites`](agent-skills/codex/build-daily-inspiration-sites/SKILL.md)** — Генерация серии оригинальных лендингов на базе ежедневной подборки UI-референсов.
- **[`daily-ui-inspiration-capture`](agent-skills/codex/daily-ui-inspiration-capture/SKILL.md)** — Автоматизированный цикл сбора, скриншотинга и упаковки свежих UI-референсов.
- **[`elevenlabs-tts`](agent-skills/codex/elevenlabs-tts/SKILL.md)** — Озвучка текстов и сценариев через ElevenLabs TTS с использованием голосовых профилей.
- **[`generate-reference-inspired-brand-worlds`](agent-skills/codex/generate-reference-inspired-brand-worlds/SKILL.md)** — Генерация самобытных визуальных миров бренда по мотивам референса с контролем дистанции от оригинала.
- **[`html-to-interaction-prompts`](agent-skills/codex/html-to-interaction-prompts/SKILL.md)** — Деконструкция готовой HTML-страницы на переиспользуемые промпты отдельных секций и интеракций.
- **[`implement-fog-of-war`](agent-skills/codex/implement-fog-of-war/SKILL.md)** — Реализация и отладка мягкого тумана войны с учётом стен и видимости в Three.js играх.
- **[`iterate-until-verified`](agent-skills/codex/iterate-until-verified/SKILL.md)** — Цикл итеративного выполнения и верификации сложных задач до полного подтверждения результата.
- **[`optimize-web-animations`](agent-skills/codex/optimize-web-animations/SKILL.md)** — Профилирование фронтенда, поиск утечек памяти и оптимизация анимаций под стабильные 60 FPS.
- **[`performance-profiling`](agent-skills/codex/performance-profiling/SKILL.md)** — Профилирование производительности приложений на платформах Apple (Instruments, Xcode, MetricKit).
- **[`stitched-full-page-capture`](agent-skills/codex/stitched-full-page-capture/SKILL.md)** — Надёжная склейка полностраничных скриншотов для сайтов с lazy-load, WebGL и скролл-анимациями.
- **[`video-to-superprompt`](agent-skills/codex/video-to-superprompt/SKILL.md)** — Превращение видеозаписи интерфейса или анимации в детальный супер-промпт для генерации вёрстки.
- **[`write-like-meng-on-x`](agent-skills/codex/write-like-meng-on-x/SKILL.md)** — Написание и редактура лаконичных продуктово-дизайнерских постов для X/Twitter в стиле Meng To.
- **[`x-bookmark-quote-posts`](agent-skills/codex/x-bookmark-quote-posts/SKILL.md)** — Превращение сохранённых закладок X/Twitter в черновики осмысленных quote-постов.

---

### 4. Разработка игр / Three.js ([`agent-skills/game-development/`](agent-skills/game-development/README.md))

- **[`author-game-levels`](agent-skills/game-development/author-game-levels/SKILL.md)** — Проектирование читаемых игровых уровней в Three.js: маршруты, коллизии, ориентиры и освещение.
- **[`build-game-audio-feedback`](agent-skills/game-development/build-game-audio-feedback/SKILL.md)** — Звуковой отклик для веб-игр: боевые слои, пространственный звук, состояния музыки и микширование.
- **[`build-game-camera-controls`](agent-skills/game-development/build-game-camera-controls/SKILL.md)** — Игровые камеры в Three.js: изометрия, слежение, lock-on, окклюзия, шейк и тач-управление.
- **[`build-game-changelog`](agent-skills/game-development/build-game-changelog/SKILL.md)** — Внутриигровой чейнджлог с версионированием, навигацией из меню и историей релизов.
- **[`build-game-inventory`](agent-skills/game-development/build-game-inventory/SKILL.md)** — Система инвентаря, лута, экипировки, тултипов, drag-and-drop и сохранений.
- **[`build-game-map-editor`](agent-skills/game-development/build-game-map-editor/SKILL.md)** — Браузерный редактор карт, связанный с боевым рантаймом Three.js/изометрических игр.
- **[`build-game-monster-system`](agent-skills/game-development/build-game-monster-system/SKILL.md)** — Интеграция риггированных монстров: сокеты, коллайдеры, стейт-машина анимаций и LOD.
- **[`build-hybrid-game-assets`](agent-skills/game-development/build-hybrid-game-assets/SKILL.md)** — Гибридный ассет-пайплайн для веб-игр: сочетание импортируемых 3D-мешей и процедурной геометрии.
- **[`build-isometric-arpg`](agent-skills/game-development/build-isometric-arpg/SKILL.md)** — Архитектура играбельной изометрической Action RPG на Three.js / React.
- **[`build-mobile-threejs-games`](agent-skills/game-development/build-mobile-threejs-games/SKILL.md)** — Адаптация Three.js игр под мобильный веб: тач-контролы, выбор целей, safe areas и бюджет производительности.
- **[`build-threejs-enemy-systems`](agent-skills/game-development/build-threejs-enemy-systems/SKILL.md)** — Дата-дривен архетипы врагов, мувсеты и контракты моделей для экшен-игр.
- **[`build-vesperfall-review-assets`](agent-skills/game-development/build-vesperfall-review-assets/SKILL.md)** — Сборка пар ревью-ассетов (PNG-референс + живая 3D-модель) для библиотеки игровых объектов.
- **[`create-game-vfx`](agent-skills/game-development/create-game-vfx/SKILL.md)** — Читаемые и производительные визуальные эффекты (удары, следы заклинаний, частицы, шейдеры) в Three.js.
- **[`design-action-combat`](agent-skills/game-development/design-action-combat/SKILL.md)** — Тактическая боевая система: тайминги атак, окна блока и уклонения, хитстоп и читаемость ударов.
- **[`design-game-encounters`](agent-skills/game-development/design-game-encounters/SKILL.md)** — Дизайн боевых столкновений: геометрия арен, состав волн, темп спавна и фазы боссов.
- **[`optimize-threejs-games`](agent-skills/game-development/optimize-threejs-games/SKILL.md)** — Профилирование и оптимизация Three.js/WebGL игр (draw calls, CPU/GPU, память) без потери качества геймплея.
- **[`ship-web-games`](agent-skills/game-development/ship-web-games/SKILL.md)** — Сборка, доставка ассетов, деплой и релизная проверка браузерных игр.
- **[`test-playable-web-games`](agent-skills/game-development/test-playable-web-games/SKILL.md)** — End-to-end тестирование браузерных игр с детерминированными фикстурами и проверкой в реальном браузере.
- **[`tune-enemy-ai`](agent-skills/game-development/tune-enemy-ai/SKILL.md)** — Настройка боевого ИИ врагов: агро, выбор цели, навигация, дистанция и телеграфирование атак.

---

### 5. Безопасность и криптография ([`agent-skills/security-crypto/`](agent-skills/security-crypto/README.md))

- **[`applied-cryptography-engineering`](agent-skills/security-crypto/applied-cryptography-engineering/SKILL.md)** — Выбор и реализация криптопримитивов: AEAD (AES-256-GCM, XChaCha20-Poly1305), X25519/Ed25519, пост-квантовые гибриды ML-KEM-768, CSPRNG.
- **[`cryptographic-audit-and-fuzzing`](agent-skills/security-crypto/cryptographic-audit-and-fuzzing/SKILL.md)** — Фаззинг бинарных парсеров (libFuzzer, AFL++, cargo-fuzz + ASan), тестовые векторы Wycheproof и релизный аудит.
- **[`cryptographic-file-format-design`](agent-skills/security-crypto/cryptographic-file-format-design/SKILL.md)** — Проектирование защищённых форматов файлов и контейнеров: бинарный заголовок, AAD, потоковое чанковое шифрование (64 KB).
- **[`secure-application-architecture`](agent-skills/security-crypto/secure-application-architecture/SKILL.md)** — Безопасная архитектура крипто-приложений: моделирование угроз STRIDE, изоляция процессов, работа без утечек во временные файлы, Fail-Closed.
- **[`secure-key-derivation-and-management`](agent-skills/security-crypto/secure-key-derivation-and-management/SKILL.md)** — Деривация и жизненный цикл ключей: Argon2id, HKDF, Envelope Encryption (Master Key → KEK → DEK), блокировка и затирание ОЗУ (`mlock`, `explicit_bzero`).
- **[`side-channel-and-anti-tamper-defense`](agent-skills/security-crypto/side-channel-and-anti-tamper-defense/SKILL.md)** — Constant-time программирование, защита от атак по сторонним каналам и харденинг бинарников (RELRO, Stack Canaries, ASLR, CFG).

---

### 6. Медиа и визуальные ассеты (`agent-skills/media/`)

- **[`aura-asset-images`](agent-skills/media/aura-asset-images/SKILL.md)** — Подбор высококачественных фоновых, портретных и редакционных изображений из библиотеки Aura Assets.
- **[`unsplash-asset-images`](agent-skills/media/unsplash-asset-images/SKILL.md)** — Подбор проверенных изображений с Unsplash для продуктовых интерфейсов, аватаров и обложек.

---

### 7. Яндекс Игры (`agent-skills/YA_SKILLS/`)

- **[`yandex-games-moderation-auditor`](agent-skills/YA_SKILLS/yandex-games-moderation-auditor.md)** — Технический и продуктовый аудит HTML5/Web-игр на соответствие требованиям модерации Яндекс Игр с оценкой рисков отклонения.
- **[`yandex-games-auto-fixer`](agent-skills/YA_SKILLS/yandex-games-auto-fixer.md)** — Автоматизированное внесение исправлений в код веб-игры по итогам аудита для успешного прохождения модерации Яндекс Игр.

---

## Демо и галерея скриншотов

Многие навыки снабжены готовыми локальными демо (`demo/index.html`) и промптами воссоздания (`demo/PROMPT.md`):
- Индекс демо и промптов: [DEMOS.md](DEMOS.md)
- Галерея рендеров: [SCREENSHOTS.md](SCREENSHOTS.md) и интерактивная страница [SCREENSHOTS.html](SCREENSHOTS.html)

Запуск любого локального демо:
```bash
python3 -m http.server 4173 -d agent-skills/<category>/<skill-name>/demo
```

---

## Лицензия

Распространяется под лицензией [MIT](LICENSE).
