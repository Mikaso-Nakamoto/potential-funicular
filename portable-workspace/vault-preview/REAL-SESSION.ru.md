# VIC-A: ручной lifecycle-тест настоящих бинарников

Предыдущие Windows-отчёты пользователя: ValidateOnly и два synthetic lifecycle сценария PASS.
Этот НОВЫЙ тест здесь не выполнялся на Windows. Статический разбор не заменяет запуск.

## Требования

Windows PowerShell 5.1 x64, обычные права. Закройте LibreWolf и освободите порт 17890.
Не завершайте незнакомые процессы. Не отключайте защиту, проверку подписей или execution policy.
Подтвердите, что Runtime/Xray и Runtime/LibreWolf установлены ранее из официальных источников.
Параметр ConfirmOfficialInstalledBinaries — ваше подтверждение происхождения, не цифровая подпись.
Xray должен совпадать с уже протестированным экземпляром SHA256
1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185.
LibreWolf должен иметь действительную Authenticode-подпись OSSign (Scheibling Consulting AB).
Если проверки не проходят, не обходите их. Подпись EXE не удостоверяет весь каталог/DLL.
Это не защита от враждебного хоста, подмены файлов/TOCTOU или DLL preload.

## Что делает тест

Start-RealVaultSession.ps1 устанавливает закреплённую libsodium в пакет и запускает
Test-RealVaultSession.ps1 в отдельном PowerShell. Только Xray и LibreWolf копируются
из InstalledRoot в owned .real-session-GUID рядом с тестом на SSD. Рабочий private,
подписка, конфиг и профиль НЕ копируются и НЕ изменяются. Нужен запас места для бинарников.
Reparse points в деревьях бинарников отклоняются. Источники не скачиваются заново.

Создаётся новый synthetic vault с example.invalid и случайным паролем в памяти.
Launcher остаётся без изменений. Harness подменяет только ввод пароля, а вызов
Start-Process оборачивает наблюдением: проверяет путь PID-владельца порта, занятый lock,
делает SOCKS5 greeting без CONNECT, затем вызывает настоящий Start-Process.
Реальный LibreWolf открывает about:blank в новом отдельном профиле. Не вводите данные,
не открывайте сайты, не скачивайте файлы. Подождите несколько секунд и закройте браузер
обычным крестиком. Окно PowerShell оставьте открытым до завершения.

После возврата проверяются завершение browser starter и Xray PID, отсутствие browser
из staged installation, освобождение порта/lock и неизменность synthetic vault.
Успех означает только этот normal-exit lifecycle, не фактическую отрисовку UI.
Это НЕ проверка внешнего трафика, IP/DNS, отключения туннеля или реальной подписки.
Браузер может пытаться делать фоновые запросы: нулевой сетевой трафик не обещается.
Не тестируются аварийное закрытие shell, hostile descendants и Job Object containment.

В finally пароль освобождается, TEMP/TMP восстанавливаются. Owned stage удаляется только
при успешной проверке процессов и свободного lock. При неопределённости stage сохраняется;
процессы принудительно не завершаются. Не удаляйте stage вручную, пока процессы используют его.
Удаление тестового каталога не означает безопасное стирание с SSD. Профиль не зашифрован.

## Запуск после распаковки в НОВЫЙ Vault-Real-Session-Test

```powershell
& 'Z:\Iran\Browser\Vault-Real-Session-Test\vault-preview\Start-RealVaultSession.ps1' -InstalledRoot 'Z:\Iran\Browser\Runtime' -ConfirmOfficialInstalledBinaries
```

Отчёт: vault-preview/real-vault-session-report.txt. При ошибке установки libsodium
до запуска теста отчёта может не быть — пришлите консольную ошибку.
Никакой миграции, удаления plaintext или переключения рабочего меню этот пакет не делает.
