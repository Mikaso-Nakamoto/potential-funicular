# Код и люди — учебный журнал

Статический сайт из трёх статей. Только HTML5: без CSS, без JavaScript, без сборщиков и зависимостей.

## Страницы

| Файл | Назначение |
| --- | --- |
| `index.html` | Главная: приветственный блок, карточки новостей, описание выпуска |
| `linus-torvalds.html` | Статья 1 — Линус Торвальдс, Linux и Git |
| `terry-davis.html` | Статья 2 — Терри Дэвис, биография создателя TempleOS |
| `templeos-holyc.html` | Статья 3 — TempleOS и язык HolyC: технический разбор |
| `login.html` | Авторизация: вход, регистрация, восстановление доступа |

`images/` — оптимизированные иллюстрации и скриншоты со ссылками на источники в подписях.

## Что использовано

- Семантика: `header`, `nav`, `main`, `article`, `section`, `aside`, `figure`/`figcaption`,
  `hgroup`, `table` с `caption`/`thead`/`tbody`/`tfoot`, `dl`, `details`/`summary`,
  `time`, `abbr`, `blockquote` с `cite`, хлебные крошки, `aria-*` и `rel="prev/next"`.
- Медиа: изображения с `width`/`height`/`alt`, встроенное видео через `iframe` (YouTube),
  аудио через `<audio>` (запись голоса Линуса Торвальдса, Wikimedia Commons, GPL v2).

## Запуск

Открыть `index.html` в браузере или поднять любой статический сервер:

```bash
python3 -m http.server 8000
```
