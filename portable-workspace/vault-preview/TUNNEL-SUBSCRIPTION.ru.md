# Живой read-only запрос: Windows curl → owned Xray SOCKS5h → subscription

Причина проверки: URL/HWID в vault совпали с текущими значениями пользователя;
.NET-запросы с v2rayNG и INCY/3.0.28 получили по две неподдерживаемые записи.
По описанию пользователя старое автообновление использовало curl через рабочий туннель.
Этот тест проверяет КОМБИНАЦИЮ curl+туннель, не выделяет одну причинную переменную.
Оригинальные старые start.ps1/vless-lib.ps1 в репозитории отсутствуют; описание не выдаём
за проверенный исходный код. Данный fetch не утверждается точной копией старого.

## Использование существующего диагностического пакета
Два новых файла CurlPipe.cs и Test-TunnelSubscription.ps1 положить в
Z:\Iran\Browser\Vault-Refresh-Diagnosis\vault-preview. Используются уже установленные
Vault.Common/XrayPipe.Common/VaultRefresh.Diagnostics/lib из этого пакета.
Запускать в новом Windows PowerShell 5.1 x64 -NoProfile, обычные права:

```powershell
& 'Z:\Iran\Browser\Vault-Refresh-Diagnosis\vault-preview\Test-TunnelSubscription.ps1'
```

Закрыть управляемую браузерную сессию: общий lock и порт 17890 должны быть свободны.
Скрипт НЕ просит пользователя запускать другой launcher: сам владеет Xray весь тест.
Существующие процессы не завершает. Ввод — только текущая фраза vault.
Проверяется pinned SHA256 прежнего Xray. Curl берётся ТОЛЬКО из Windows System32,
требуется Valid Authenticode / Microsoft Corporation, без обходов/скачивания EXE.
C# source pin проверяется перед компиляцией. TEMP/TMP на Runtime/private/tmp до crypto.

## Сетевое поведение и секреты
Нативный Xray -test stdin → BeginRun/Send → проверка loopback listener именно этого PID.
Windows curl запускается с фиксированными args `-q --config -`: -q первым запрещает curlrc.
URL и headers передаются только через stdin, не args, environment или временный config.
User-Agent INCY/3.0.28, сохранённый x-hwid. Явный socks5h proxy и пустой noproxy подавляют
обход через NO_PROXY; hostname разрешается удалённо. Только HTTPS, redirect не следует,
сертификаты проверяет Windows curl без insecure/ssl-no-revoke. Проверяется HTTP 200.
Не загружается рабочий browser profile, браузер не запускается.

Connect timeout 10s, curl max-time 30s, managed writer 5s/process wait 35s + bounded drain/
cleanup waits. Это не абсолютная гарантия времени при зависшей ОС/неподтверждаемом cleanup.
stdout ограничен 4 MiB + 256 bytes для status; stderr 64 KiB, всегда отбрасывается.
Переполнение/ненулевой curl exit/невалидный UTF-8/не-200 — отказ, без native diagnostics.
SSLKEYLOGFILE удалён из child environment; нет обещания защиты от hostile host/preload.
Буферы очищаются, managed strings/копии CLR гарантированно не стираются.

В ответе выводятся только FORMAT/ENTRIES/REJECT/SHAPE и HTTP status. Response/config не
записываются. Hash ciphertext до/после проверяет неизменность vault; не anti-TOCTOU гарантия.
В finally сначала очистка curl, затем Xray; session lock отпускается только после
CleanupConfirmed обоих. Если очистка не подтверждается — предупреждение и ожидание,
не ложный success. Принудительное закрытие PowerShell/всего хоста не управляется.
Нет Job Object, гарантии всех descendants и защиты от локального противника.

## Статус
Новые C#/PS файлы здесь прошли статический разбор и source-contract проверки, НЕ Windows
компиляцию/исполнение. Прежние Windows PASS не подтверждают новый curl helper.
После запроса дождитесь возврата приглашения PowerShell. Пришлите только безопасную
сводку. Vault, backup, URL/HWID/фразу/сырые links не присылать.
Никакой записи нового vault/rollback/refresh пока нет. Тест не меняет TLS/парсер политику.
