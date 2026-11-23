# Следующий этап: изолированный транспорт конфигурации Xray через stdin

## Исправление протокола теста (stdin kit R2)

Первый Windows-отчёт для f302f88 показал успешные baseline/reject/hang/flood, но
после сообщения blocked-writer PASS не оказалось PID-маркера. Причина отсутствия
маркера из этого отчёта не установлена: ранний PASS не доказывал достижение
нужной ветки fixture. Реальный Xray тогда ещё НЕ был проверен.

Теперь BeginValidation создаёт процесс и drains, но ещё не отправляет stdin.
Тест ждёт до 15 секунд два маркера с PID именно этого процесса, включая marker
из ветки fixture, которая намеренно НЕ читает stdin. Только затем SendAndValidate
подаёт 4 МиБ и включает прежний 3-секундный deadline записи. Прежний таймаут не
увеличен ради PASS. Итог PASS печатается только после нужной категории ошибки,
CleanupConfirmed и проверки выхода правильного child. Startup/readiness failure
отдельно проваливает набор; отсутствие marker не считается успешным таймаутом.

BeginValidation — низкоуровневый двухфазный API. Он не обещает готовность настоящего
Xray: handshake существует только у тестового fixture. С момента возврата caller
владеет Session и обязан ограничить ожидание/вызвать Dispose даже до передачи JSON.
Обычные Start/Validate сохраняют прежние сигнатуры и фиксированные аргументы.
R2 пока прошёл только статический разбор, нужен новый Windows-запуск.

## Статус

Это НОВЫЙ, ещё не исполненный на Windows код; успешные vault R3 отчёты его не покрывают.
Рабочие Start-Workspace.ps1, Update-Subscription.ps1 и меню НЕ изменены. Подключение
пока не переведено на vault, нет подписочного encrypted refresh и миграции.
Не удалять xray.json. Этот пакет проверяет только следующий строительный блок.

## Реализация

XrayPipe.cs: фиксированные аргументы `run -config stdin: -format json`, для
проверки — `run -test -config stdin: -format json`. Поддержка flags/stdin сверена
с официальным XTLS/Xray-core v26.11.9: main/run.go и main/confloader/external/external.go.
Конфиг — UTF-8 bytes в StandardInput.BaseStream, затем EOF. Не передаётся аргументом,
не пишется в файл. stdout/stderr читаются одновременно в отдельных потоках в
4096-байтовые буферы и стираются; вывод не собирается в строки/логи. Больше 1 МиБ
на любом потоке — остановка дочернего процесса. Ошибки наружу только фиксированные,
без native exception chain, stderr/stdout и JSON.

Есть отдельные таймауты записи stdin и ожидания выхода. Drain deadline 5 секунд,
cleanup wait до 8 секунд: managed waits не более 2*timeout + 13 секунд для Validate.
Это не жёсткая real-time гарантия для OS start/kill/scheduler и враждебного хоста.
Запись получает отдельную ограниченную копию конфигурации, очищаемую writer в finally;
обёртка очищает исходный byte[] в finally. Managed JSON-строки не гарантированно стираются.

Start возвращает объект с Id/HasExited/HasFailed/Dispose/CleanupConfirmed, а не
открытые output streams. CleanupConfirmed обязателен для будущего launcher перед
освобождением lock: при некооперативном процессе/унаследованной pipe cleanup может
не завершиться; возвращение Dispose само по себе не означает успех. Background
workers могут оставаться при таких отказах. Это НЕ Job Object и не управление
всем деревом процессов. Существующие ограничения принудительного закрытия shell
не устранены. Сначала требуется Windows-проверка и отдельное lifecycle-ревью.

XrayPipe.Common.ps1 проверяет хеш точных байтов C#, компилируемых Add-Type,
валидирует Config через прежнюю Assert-ConfigObjectPolicy ПЕРЕД запуском, затем
сериализует в памяти. Хеш rooted in trusted scripts, не подпись поставки.
Низкоуровневый Session не валидирует tunnel policy — это обязанность обёртки.
Доверенный исполняемый файл обязателен: helper не аутентифицирует произвольный EXE.

## Что проверяет Test-XrayPipe

Локально компилирует синтетический .NET EXE во вновь созданный owned scratch.
Никакого запуска PowerShell-команд из JSON, скачивания инструментов или сети.
Fixture проверяет точные аргументы, читает stdin до EOF, намеренно пишет секрет-маркер
в stdout/stderr (он не должен появиться в отчёте), может вернуть exit23, зависнуть,
не читать stdin, заполнить stderr/stdout или оставаться живым до Dispose.
Тесты требуют отклонения/таймаутов и подтверждают завершение child. Проверяется также
policy rejection ДО создания child. Не доказывает злонамеренные descendants/все OS races.

Опциональный -XrayExe читает ТОЛЬКО установленный EXE для его хеша и запускает его
в `-test` с синтетическим example.invalid TLS/VLESS-конфигом. Не читает реальные
Runtime/private файлы, не открывает SOCKS, не проверяет подключение к серверу.
Двоичный файл должен быть ранее установлен из доверенного официального источника;
записанный хеш сам по себе не доказывает его происхождение. Без -XrayExe реальная
совместимость явно помечается NOT RUN, а не выдаётся за проверенную fake-тестами.

## Как воспроизвести на Windows

Сохранить VIC-A-Xray-Stdin-Tests-R2.zip в Z:\Iran\Browser. Обычный 64-bit Windows
PowerShell 5.1, не x86, не администратор. Xray-Stdin-Test-R2 — новый пустой каталог.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Unblock-File -LiteralPath 'Z:\Iran\Browser\VIC-A-Xray-Stdin-Tests-R2.zip'
    Expand-Archive -LiteralPath 'Z:\Iran\Browser\VIC-A-Xray-Stdin-Tests-R2.zip' -DestinationPath 'Z:\Iran\Browser\Xray-Stdin-Test-R2'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Xray-Stdin-Test-R2\vault-preview\Test-XrayPipe.ps1' -XrayExe 'Z:\Iran\Browser\Runtime\Xray\xray.exe'
}
```

Отчёт: Z:\Iran\Browser\Xray-Stdin-Test-R2\vault-preview\xray-pipe-test-report.txt.
Передать его для разбора, не конфиги/URL/пароли. TEMP/TMP на время теста направлены
в stage на этом диске. Stage удаляется в finally; после аварии может остаться
синтетический fixture/состояние, но не реальные подписки. OS pagefile/logs не контролируются.
Тесты синтетические, сгенерированные EXE не сохраняются в Git/ZIP. Администратор,
Bypass и изменение системной политики не нужны. Если защитное ПО блокирует fixture,
не отключать его — передать ошибку.
