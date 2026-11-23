# Рабочий vault: отдельная encrypted COPY, не миграция

## Статус
Пользовательские Windows-отчёты: synthetic negative/lifecycle и normal-exit lifecycle с
настоящими Xray/LibreWolf PASS. НОВЫЕ Prepare-WorkingVault и wrapper здесь прошли только
статический разбор, не Windows execution. Проверка рабочего конфига и соединения ещё впереди.

## Перед запуском
Закройте LibreWolf и освободите 17890, не убивая неизвестные процессы. Windows PS5.1 x64,
обычный пользователь. Достаточно места для ещё одной копии Xray/LibreWolf на том же SSD.
Подтвердите официальное происхождение установленного Xray/LibreWolf. Xray закреплён на
ранее проверенный SHA256 1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185;
LibreWolf требует Valid Authenticode и OSSign (Scheibling Consulting AB). Бинарники не
скачиваются заново. Подпись EXE не удостоверяет все DLL/архив. Нет защиты от враждебного
хоста, preload, TOCTOU, подмены исходного Runtime. Не отключайте защиту ради скрипта.

## Prepare
Start-WorkingVaultPreview.ps1 -Action Prepare -ConfirmOfficialInstalledBinaries

Installer ставит ту же закреплённую libsodium в пакет. Новый PS-процесс берёт session lock
исходного Runtime, читает ограниченный snapshot private/xray.json только в память,
проверяет policy. Копирует ТОЛЬКО каталоги Xray и LibreWolf в owned .working-vault-GUID,
проверяет staged EXE, выполняет нативный Xray -test через stdin. Профиль не копируется.
Скрипт не делает subscription request и не проверяет актуальность узла через сеть.

Затем скрыто запросит полный существующий HTTPS URL и прежний рабочий HWID UUID.
HWID не генерируется заново; используйте уже успешно работавший с провайдером.
Значения сохранятся только в encrypted vault. Не присылайте их в чат.
Шесть случайных слов показываются ОДИН РАЗ в консоли: запишите безопасно и повторите
по запросу. Не используйте запись экрана/транскрипт; слова останутся в scrollback.
Пароль нельзя восстановить. Управляемые строки не гарантированно стираются из памяти.

После authenticated read-back весь готовый каталог публикуется как WorkingRuntime
рядом с верхнеуровневым Start-VaultWorkspace.ps1. Существующий WorkingRuntime никогда
не перезаписывается/не объединяется. Исходный xray.json и профиль не изменяются,
новый plaintext JSON не создаётся. Создание .session.lock в исходном Runtime возможно.
При сбое stage сохраняется (может содержать encrypted vault); не удаляйте, пока процессы
его используют. Это не crash-durability гарантия и не протокол backup.

## Validate отдельно
Start-WorkingVaultPreview.ps1 -Action Validate

В НОВОМ PS-процессе запросит созданную фразу и вызовет настоящий launcher ValidateOnly.
Без браузера, listener и подключения. При неверном пароле/повреждении — без fallback.
На этом остановитесь и сообщите только PASS/ошибку без секретов. Рабочий сетевой сеанс,
SOCKS CONNECT, IP/DNS и tunnel-disconnect будут отдельным следующим шагом.

## Ограничения
Это НЕ перевод всей установки на пароль: legacy launcher/plaintext остаются обходом.
Меню/обновление/выбор узла не переключены. Нет encrypted refresh, удаления plaintext,
безопасного стирания SSD, шифрования browser profile, Job Object containment.
Не запускайте обычный обновлятор на WorkingRuntime: encrypted updater ещё не реализован.
Не отправляйте vault/config/скриншот фразы в чат. Для обсуждения ошибок используйте
сообщение об этапе, без внутреннего exception/config values.
