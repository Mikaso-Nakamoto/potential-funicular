# VIC-A Vault Test Kit R3 — только изолированные тесты

Не миграция. Не читает Runtime/подписку/профиль и не запускает Xray или браузер.
Содержит только синтетические fixture; случайные фразы тестов никогда не печатаются.
Prepare-Vault (реальное создание копии) в тестовый ZIP не включён.

## Что новое

Генератор шести слов EFF, System32-only dependency search, контроль хешей helper,
полные копии для мутаций, baseline перед ними, canary-тест соседней runtime DLL,
отчёт с SHA-256 входов и версиями PS/CLR/ОС. R2 PASS не подтверждает R3.
R3 PowerShell/C# здесь не запускались и не компилировались — нужен новый тест.

MSVC libsodium 1.0.22 скачивается только из официального релиза с pinned SHA-256.
VC runtime в System32 должен уже присутствовать и иметь Valid Microsoft signature;
ничего системного не устанавливается, нет admin/Bypass/скачивания DLL с других сайтов.
Не редактировать allowlist/хеши ради PASS. Если prerequisite отсутствует, остановиться.

## Запуск (64-битный Windows PowerShell 5.1, не x86, без администратора)

Сохранить ZIP как Z:\Iran\Browser\VIC-A-Vault-Test-Kit-R3.zip.
Каталог Vault-Test-R3 должен быть новым и пустым; не распаковывать поверх R2/Runtime.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Unblock-File -LiteralPath 'Z:\Iran\Browser\VIC-A-Vault-Test-Kit-R3.zip'
    Expand-Archive -LiteralPath 'Z:\Iran\Browser\VIC-A-Vault-Test-Kit-R3.zip' -DestinationPath 'Z:\Iran\Browser\Vault-Test-R3'
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Vault-Test-R3\vault-preview\Start-VaultCheck.ps1'
}
```

Start-VaultCheck останавливается при ошибке установки до запуска тестов.
Логи из Z:\Iran\Browser\Vault-Test-R3\vault-preview:
- vault-install-report.txt — результат установки/причина раннего отказа;
- vault-test-report.txt — полный протокол тестов и SHA-256 входов.
Прислать оба файла, если оба созданы. В них могут быть локальные имена каталогов;
реальные URL/UUID/пароли и файлы из Runtime не присылать.

Чтобы повторить тесты ПОСЛЕ успешной установки (не повторять Start-VaultCheck):
```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File 'Z:\Iran\Browser\Vault-Test-R3\vault-preview\Run-VaultTests.ps1'
```

## Границы результата

Canary — намеренно недопустимый образ, не вредоносная исполняемая DLL. Проверяется,
что он не мешает инициализации и VC runtime загружен из System32. Если runtime уже
был в процессе, runner напечатает LIMITATION, а не объявит доказанным first-load.
Даже PASS не доказывает все состояния загрузчика и безопасность враждебного хоста.
Нет теста disk-full/power loss/unplug, hostile ZIP suite, CPU без AES, чистой Windows
и end-to-end миграции. Файловые тесты работают только в собственном scratch каталоге.
Таймаут дочернего набора — 120 секунд. TEMP/TMP направлены на тестовый диск в owned
stage; системные журналы/pagefile этим не контролируются. После аварийного завершения
scratch может остаться с тестовыми данными. Старый открытый рабочий конфиг не удалять.
