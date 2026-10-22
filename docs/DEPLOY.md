# Установка на свой сервер (Linux Mint, старый ноутбук)

Бот — это один Python-процесс и один файл SQLite. Никаких баз-серверов, docker и
веб-серверов не нужно. Внешние зависимости: **никаких** (Python 3.11+ уже
содержит всё нужное).

По времени: 10 минут, если сообщество ВК уже настроено ([VK_SETUP.md](VK_SETUP.md)).

---

## 1. Проверить систему

```bash
python3 -V                 # нужно 3.11 или новее
timedatectl                # время и часовой пояс должны быть верными
```

Если Python старее 3.11 (Linux Mint 21.x даёт 3.10) — два варианта:

```bash
sudo apt install python3-tomli        # минимум, чтобы читался config.toml
# или полноценно:
sudo apt update && sudo apt install python3.11 python3.11-venv
```

Если время/часовой пояс неверные — напоминания будут приходить не тогда:

```bash
sudo timedatectl set-ntp true
sudo timedatectl set-timezone Europe/Moscow
```

## 2. Скачать код

```bash
cd ~
git clone https://github.com/Mikaso-Nakamoto/potential-funicular.git massage-bot
cd massage-bot
```

Если git не стоит: `sudo apt install git`.
Если нет доступа к GitHub — просто скопируйте папку проекта на флешке и
положите в `~/massage-bot`.

## 3. Настроить под себя

```bash
cp config.example.toml config.toml
cp .env.example .env
chmod 600 .env
nano config.toml      # услуги, расписание, контакты, тексты
nano .env             # VK_GROUP_ID, VK_GROUP_TOKEN, ADMIN_VK_IDS
```

Что обязательно поправить в `config.toml`:

| Секция | Что заполнить |
|---|---|
| `[[services]]` | реальные услуги, длительность в минутах, цены |
| `[schedule.hours]` | рабочие часы по дням; пустой список = выходной |
| `[schedule]` `timezone` в `[bot]` | город мастера (`Europe/Moscow`, `Europe/Samara`…) |
| `[contacts]` | телефон, WhatsApp, Telegram, страница ВК, адрес — это видят клиенты |
| `[reminders]` | за сколько часов напоминать клиенту и мастеру |
| `[admin]` `vk_ids` | можно оставить пустым и задать в `.env` |

## 4. Проверить, не запуская бота

```bash
python3 scripts/doctor.py --all
```

Отдельно полезно посмотреть, как расписание превращается в окна для записи:

```bash
python3 scripts/doctor.py --slots
```

И пощупать сценарий руками без ВК (терминал вместо мессенджера):

```bash
python3 scripts/demo.py           # интерактивно: !admin — стать мастером, !time +1d — мотать время
python3 scripts/demo.py --auto    # посмотреть весь сценарий за 5 секунд
```

## 5. Запустить вручную (первый раз)

```bash
python3 -m bot.main
```

В логе должно быть:

```
Подключился к сообществу: Массаж · Елена · Тверь (@massage_elena, id=123456789)
Слушаю сообщения сообщества… (Ctrl+C — остановка)
```

Напишите боту с телефона, пройдите запись до конца, подтвердите заявку со
страницы тёти. Если всё хорошо — останавливайте (Ctrl+C) и ставьте как службу.

## 6. Запустить как службу (systemd) — чтобы жил сам

```bash
sudo cp systemd/massage-bot.service /etc/systemd/system/massage-bot.service
sudo nano /etc/systemd/system/massage-bot.service
```

Поменяйте в файле **три строки** (в двух местах, включая `ReadWritePaths`):

```ini
User=ВАШ_ПОЛЬЗОВАТЕЛЬ
WorkingDirectory=/home/ВАШ_ПОЛЬЗОВАТЕЛЬ/massage-bot
ReadWritePaths=/home/ВАШ_ПОЛЬЗОВАТЕЛЬ/massage-bot/data
```

Имя пользователя узнаете командой `whoami`, путь — командой `pwd`.

Дальше:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now massage-bot     # запуск + автозапуск при включении
systemctl status massage-bot                # должно быть active (running)
journalctl -u massage-bot -f                # живой лог
```

Полезные команды:

```bash
sudo systemctl restart massage-bot    # после правки config.toml
sudo systemctl stop massage-bot       # остановить
sudo systemctl disable massage-bot    # не запускать при старте системы
```

> ⚠️ Не держите бот запущенным дважды (службой и руками в терминале) — ответы
> задвоятся. Защита от этого встроена: второй экземпляр скажет «Бот уже запущен»
> и выйдет.

## 7. Ноутбук как сервер: не давать ему засыпать

Это самая частая причина «бот внезапно перестал отвечать». Старый ноутбук с
закрытой крышкой уходит в сон вместе с ботом.

```bash
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Проверка: закрыли крышку, через минуту написали боту — он отвечает.

Ещё по мелочи для сервера-ноутбука:

- питание: оставьте зарядник подключённым;
- сеть: лучше кабель, чем Wi-Fi; если Wi-Fi — отключите энергосбережение
  адаптера (`sudo iw dev wlan0 set power_save off`);
- автологин включать **не нужно**, службе достаточно загрузки системы;
- обновления безопасности: `sudo apt update && sudo apt upgrade` раз в месяц
  (бот перезапустится сам через systemd, если понадобится).

## 8. Резервные копии базы

Вся ценность — файл `data/massage.sqlite3` (заявки, клиенты, история).

```bash
./scripts/backup_db.sh          # копия в backups/ (можно на работающем боте)
```

Автокопия каждый день в 21:30:

```bash
crontab -e
# добавить строку:
30 21 * * * cd /home/ВАШ_ПОЛЬЗОВАТЕЛЬ/massage-bot && ./scripts/backup_db.sh >> backups/backup.log 2>&1
```

Раз в неделю стоит копировать `backups/` куда-то вовне (флешка, облако,
второй компьютер) — на случай смерти ноутбука. Восстановление:

```bash
sudo systemctl stop massage-bot
gunzip -c backups/massage-20261022-213000.sqlite3.gz > data/massage.sqlite3
sudo systemctl start massage-bot
```

## 9. Обновление кода

```bash
cd ~/massage-bot
git stash                 # если правили код руками
git pull
git stash pop             # вернуть свои правки (может попросить разрешить конфликты)
python3 tests/run_all.py  # 43 теста должны пройти
sudo systemctl restart massage-bot
```

`config.toml`, `.env` и `data/` в git не попадают, поэтому обновление настройки
не затирает.

## 10. Что должно получиться

- клиент пишет сообществу → видит меню;
- выбирает услугу → дату → время → имя → телефон → отправляет заявку;
- тёте приходит заявка с кнопками **«Подтвердить» / «Отклонить» / «Перенести»**,
  телефоном клиента и ссылкой «написать клиенту»;
- после подтверждения клиенту уходит подтверждение, затем напоминания
  (за 24 ч и за 2 ч — настраивается);
- утром тёте приходит список записей на день;
- заявка без ответа закрывается сама (по умолчанию через 24 ч), клиенту приходит
  вежливое сообщение и предложение написать напрямую.

Дальше: [ADMIN_GUIDE.md](ADMIN_GUIDE.md) — инструкция для тёти (без технических слов),
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) — если что-то пошло не так.
