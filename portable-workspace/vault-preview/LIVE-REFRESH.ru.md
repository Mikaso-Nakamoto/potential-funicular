# VIC-A — controlled live refresh R2 + security self-review

См. vault-preview/SECURITY-REVIEW-2026-11.ru.md: найдено два логических дефекта,
исправлены validation ownership и TEMP-before-unlock. Новые изменения не исполнялись
здесь на Windows; старый synthetic PASS не подтверждает эту ревизию автоматически.
Криптоформат/пароль не изменены; повторно вводить URL/HWID не нужно.
Это не независимый аудит и не утверждение об отсутствии всех уязвимостей.

## 1. Сначала regression на synthetic data
Распаковать в НОВЫЙ Z:\Iran\Browser\Vault-Refresh-Live-R2.
Обычный Windows PowerShell 5.1 x64:

```powershell
& 'Z:\Iran\Browser\Vault-Refresh-Live-R2\vault-preview\Start-VaultRefreshTests.ps1'
```

Installer использует тот же pinned официальный libsodium. В свежих процессах повторяются
transport regression (с обновлённым validation wrapper) и synthetic refresh. Рабочий
Runtime/WorkingRuntime не читаются и не меняются. Браузер не запускается. Защиту не отключать.
Отчёты vault-preview/xray-pipe-test-report.txt и vault-refresh-test-report.txt.
Если ошибка — прислать отчёты, LIVE не выполнять. Installer повторно не запускать поверх lib.

## 2. Только после успешных тестов — рабочий refresh
Закройте все LibreWolf/туннельные сессии; 17890 должен быть свободен.
Нужен запас места на том же диске для нового encrypted vault и encrypted backup.

```powershell
& 'Z:\Iran\Browser\Vault-Refresh-Live-R2\vault-preview\Update-VaultSubscription.ps1' -Root 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime' -ConfirmLiveRefresh
```

Ввести ТЕКУЩИЕ шесть слов скрыто. Никакой новой фразы не создаётся.
Скрипт использует сохранённые HTTPS URL и прежний x-hwid, User-Agent v2rayNG,
запрет redirect и прежние TLS/response limits. Запрос идёт через Windows connection/
system proxy, НЕ через браузерный tunnel. Работоспособность default fetch в новом core
с провайдером ещё не подтверждена. Секреты/URL/labels/hosts на экран не выводятся.
Если прежний полный outbound совпадает ровно с одним узлом, он остаётся автоматически;
иначе будет список Node 1/2/... и запрос номера. Полный список узлов ещё не сохраняется.

Общий session lock удерживается весь refresh. Native Xray -test получает JSON через stdin,
не временный JSON. Публикация — File.Replace с уникальным encrypted backup
private/workspace.vault.backup-GUID (точные прежние ciphertext bytes).
Не удалять backup после первого успеха. Его наличие не заменяет отдельный recovery protocol.
Старый plaintext xray.json, профиль, legacy updater/menu не меняются и не удаляются.
Это не транзакционная миграция всей установки и не power-loss/disk-full гарантия.

Сообщите только PASS либо фиксированное имя этапа ошибки. Не присылайте URL/HWID,
конфиг, vault, backup и пароль. При encrypted-replacement failure не запускать blindly,
не удалять active/backup; сначала разобраться в состоянии публикации.

## 3. Проверка после success в новом PowerShell

```powershell
& 'Z:\Iran\Browser\Vault-Refresh-Live-R2\Start-VaultWorkspace.ps1' -Root 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime' -ValidateOnly
```

Введите ту же фразу. Это не проверка remote connectivity. Реальный запуск возможен тем же
launcher без ValidateOnly только после успеха; используйте НОВЫЙ launcher из этого пакета,
чтобы применялось исправление validation ownership. Старые распакованные пакеты и рабочее
меню сами не обновляются. Для повседневного переключения меню отдельного решения ещё нет.

Нет password rotation, полного node-list storage, Job Object, системного kill switch,
anti-rollback или шифрования browser profile. Подробности — security self-review.
