# VIC-A: synthetic encrypted refresh tests

## Статус и область
Ранее пользователь проверил рабочий vault→stdin→Xray→LibreWolf, рабочее соединение,
ошибку proxy при остановке Xray и освобождение порта. Это НЕ проверяет новый updater.
Новый refresh core здесь не выполнялся на Windows. Сначала только этот synthetic kit.
Никакой рабочий Runtime, WorkingRuntime, подписка или браузер НЕ используются.

Start-VaultRefreshTests.ps1 устанавливает закреплённую libsodium в пакет и запускает
Test-VaultRefresh.ps1 в свежем Windows PowerShell 5.1 x64. Нужны обычные права,
свободное место на NTFS и интернет только для установки официальной зависимости.
Сетевой fetch в тесте заменён scriptblock, вместо Xray компилируется fixture с прежним
проверенным stdin-протоколом. Не отключайте защиту при блокировке fixture.

## Новое ядро VaultRefresh.Common.ps1
Exclusive session lock → unlock → URL/HWID из vault → fetch → bounded parsing plain/Base64
списка через прежний Convert-Vless → сохранение выбранного узла при единственном полном
совпадении его канонического outbound, иначе выбор номера → policy/native stdin -test →
шифрование тем же паролем → Flush(true), disk read-back → File.Replace с уникальным
ENCRYPTED backup старого ciphertext. При ошибке Replace нет delete/move fallback.
Старые backup не перезаписываются и не удаляются автоматически.

Реальный default fetch использует прежний Get-SubscriptionText: v2rayNG User-Agent,
сохранённый x-hwid, HTTPS/TLS policy, запрет redirect, bounded read. Но в данном тесте
он НЕ вызывается и работа провайдера не проверяется. Тестируемое ядро получает fetch и
choose как зависимости; отдельный пользовательский live-updater пока не опубликован.
Ошибки наружу содержат только фиксированное имя этапа, не nested exception/URI/body.
Выбранный outbound сохраняется внутри activeConfig; URL/HWID/createdAt сохраняются.
Полный список nodes и отдельное поле selection ещё НЕ сохраняются: schema v1 не менялась.
Полное semantic identity matching при изменении полей сервером не обещается — тогда
требуется повторный выбор. Base64 — формат передачи, НЕ шифрование.

## Что проверяет набор
- неверный пароль до fetch, занятый session lock;
- fetch exception с private sentinel без отражения в ошибке;
- HTML, неверный Base64, список без поддерживаемых узлов, неверный выбор;
- отказ native validator именно на этапе native-validation;
- блокировка File.Replace открытым destination именно на этапе encrypted-replacement;
- во всех ожидаемых отказах hash active vault и число backups прежние, temp убран;
- mixed list, forwarding сохранённых URL/HWID, сохранение узла после перестановки;
- backup — точные байты старого ciphertext; metadata сохранены;
- Base64, выбор другого узла, новый vault открывается прежним паролем;
- освобождение lock, отсутствие JSON-файлов/refresh temp в тестовом Runtime.

## Ограничения
Synthetic tests не доказывают power-loss/unplug/disk-full durability, NTFS/другие FS matrix,
hostile races/TOCTOU, процессные деревья или защиту от враждебного хоста. Flush(true)+Replace
не являются полноценным crash-recovery протоколом. Если File.Replace сам отказал во время
публикации, требуется проверить encrypted active/backup, а не обещать rollback при любом сбое.
Проверка hash до Replace — диагностика изменения, не защита от параллельного вредоносного писателя.
Plaintext config/список живут в памяти; managed strings не гарантированно стираются.
Legacy launcher/updater/menu не изменены. Plaintext старой установки не удалён. Нет миграции.

## Запуск
Распаковать в новый Z:\Iran\Browser\Vault-Refresh-Test.
Запустить vault-preview\Start-VaultRefreshTests.ps1 обычным Windows PowerShell 5.1 x64.
Отчёт: vault-preview\vault-refresh-test-report.txt. До старта test-скрипта (например при
сбое installer) отчёта может не быть — тогда пришлите консольную ошибку.
В тесте только вымышленные секреты, пароль не показывается и вводить ничего не нужно.
Рабочий vault не обновлять до отдельного разрешённого шага после результатов теста.
