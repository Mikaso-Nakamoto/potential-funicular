# Read-only diagnosis of refresh parse failure

Live refresh R2 у пользователя остановился на parse. Этот этап предшествует
Write-RefreshReplacement: обновление vault не выполнялось. Причина пока не установлена.
Не присылайте raw response, URL/HWID, node links, vault или пароль.

Этот отдельный пакет не ослабляет policy и не исправляет неизвестный формат вслепую.
Новые PS-скрипты здесь только статически разобраны, не выполнены на Windows.

Start-VaultSubscriptionDiagnosis.ps1 сначала запускает synthetic tests категорий:
HTML/JSON/неверный Base64/mixed list/unsupported transport/query/fingerprint/Base64/
unknown exception с private sentinel. Затем ставит ту же закреплённую libsodium в пакет
и в новом PS5.1 x64 процессе запускает read-only diagnosis.

Под общим session lock читает существующий WorkingRuntime/private/workspace.vault
по текущему паролю, делает живой HTTPS запрос с сохранёнными URL и x-hwid через текущее
Windows connection/system proxy (не управляемый туннель). Браузер лучше закрыть.
TEMP/TMP направлены в private/tmp до unlock и восстанавливаются. Может создать tmp/lock
и helper compilation artifacts, но не пишет plaintext response/config, vault или backup.
Нативный Xray и браузер не запускаются. Проверяет неизменность hash ciphertext после чтения.
Hash — диагностика обычного изменения, не anti-TOCTOU защита от hostile host.

Вывод: только FORMAT/ENTRIES/REJECT/SHAPE с фиксированными кодами, counts и allowlisted
transport/security/fingerprint. Unknown values заменяются other; nested exceptions,
labels, hostnames, credentials и фрагменты response никогда не выводятся.
Это не доказательство отсутствия всех возможных утечек; sentinel tests — ограниченные.
Никакие URL/ссылки на узлы не сохраняются в отчёте — отдельный отчёт на диск не создаётся.

Запуск в новом Z:\Iran\Browser\Vault-Refresh-Diagnosis:

```powershell
& 'Z:\Iran\Browser\Vault-Refresh-Diagnosis\vault-preview\Start-VaultSubscriptionDiagnosis.ps1' -Root 'Z:\Iran\Browser\Working-Vault-Preview\WorkingRuntime'
```

Введите прежнюю фразу. Пришлите строки FORMAT/ENTRIES/REJECT/SHAPE и итог DIAGNOSTIC.
При сбое synthetic checks live fetch не начинается; при сбое installer отчёта не будет.
Старые launcher/updater/config/profile не меняются. Настоящий refresh не повторять
до выяснения причины. Политика TLS и поддержанные транспорты не расширялись.
