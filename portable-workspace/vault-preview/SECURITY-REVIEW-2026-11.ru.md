# Повторное ревью безопасности: vault / stdin / refresh

Это self-review кода тем же агентом, НЕ независимый аудит и НЕ сертификат отсутствия дыр.
Дата проверки в среде разработки: 2026-11-22. Windows-прогоны выполняет пользователь;
новые исправления ниже здесь только статически проверены. Исторические ZIP не изменены.

## Просмотренный объём
VaultCrypto.cs, Vault.Common.ps1, XrayPipe.cs/Common, Start-VaultWorkspace.ps1,
VaultRefresh.Common.ps1, Prepare-Vault/Prepare-WorkingVault, тесты refresh/lifecycle;
проверены также границы Get-SubscriptionText/Convert-Vless/Assert-ConfigObjectPolicy,
выбор DLL из ZIP в Install-VaultDependency. Старые plaintext Start/Update просмотрены
в части разграничения с vault-путём, но полный аудит всех старых installer/UI/menu,
всего кода LibreWolf/Xray/libsodium и всех native dependencies НЕ проводился.

## Найдены и исправлены логические дефекты

### 1. Потеря видимости cleanup при нативной валидации
Test-XrayObjectInMemory вызывал static Session.Validate. Если cleanup не подтверждался,
внешний PS-код получал ошибку, но не Session и мог выйти из finally, освободив lock.
Это не обход AES/пароля, но нарушение заявленного ownership-инварианта при сбоях.
Теперь wrapper получает BeginValidation handle ДО отправки config, вызывает
SendAndValidate и в finally ждёт CleanupConfirmed прежде возврата/ошибки вызывающему.
При неподтверждённой очистке ждёт с предупреждением, а не объявляет профиль/lock свободным.
Нормальные failure/timeout сценарии транспортного fixture нужно повторить на Windows.
Ветка с намеренно неподтверждаемым cleanup не воспроизводилась: её source contract —
не доказательство работы со всеми потомками/сбоями ОС.

Остаток: Open/Process.Start может ошибиться до возврата handle; чрезвычайные сбои
создания задач/процесса не покрыты. Без Job Object не гарантируется зачистка дерева.
Обёртка Start-XrayObjectInMemory (старый convenience API) также не предназначена для
нового lifecycle-кода: используйте Open/Send с ownership. Forced shell termination,
убийство PowerShell, выдёргивание диска и часть проблем ОС обходят managed finally.
CleanupConfirmed может остаться false навсегда; это намеренный fail-closed с потерей
доступности, а не обещание автоматического восстановления.

### 2. TEMP перенаправлялся после первой компиляции при refresh
Invoke-VaultRefresh выставлял private/tmp только перед native validation, хотя
Read-Vault мог раньше вызвать Add-Type/проверку DLL в исходном Windows TEMP.
Туда не записывался конфиг JSON, но требование размещения runtime artifacts на SSD
не соблюдалось. Теперь TEMP/TMP задаются под session lock ДО unlock и восстанавливаются.
Тот же порядок исправлен в старом Prepare-Vault; рабочий Prepare-WorkingVault уже
задавал TEMP до crypto. Старые распакованные пользователем копии сами не обновляются.

## Криптографическая конструкция: явного дефекта в просмотренном коде не найдено

- libsodium 1.0.22: AES-256-GCM, header как AAD, ciphertext + 128-bit tag;
  случайные salt 128 bit и nonce 96 bit при каждой записи, новый derived key из salt.
- Argon2id13, ops=3, memory=64 MiB, key 32 bytes. Параметры фиксированы кодом:
  редактирование header не заставляет выбрать слабый KDF/неограниченный memory cost.
- Magic/размеры ограничены до decrypt; нет публикации plaintext до успешного AEAD.
- NFC/strict UTF-8; это не исправление раскладки. Генератор: шесть независимых слов
  из 7776, unbiased randombytes_uniform, около 77.55 bit для ИМЕННО этого генератора.
  Seal допускает слабее выбранные вручную пароли как низкоуровневый API; не считать
  минимум длины оценкой энтропии. Пользовательское создание требует generated credential.
- Независимые Python vectors ранее и сейчас проверяют формат/Argon2id/AES-GCM,
  неверный пароль, tamper/truncation/NFC. Это не формальная верификация C#/PInvoke.
- Ключевые byte/char buffers очищаются; managed strings, копии CLR/JIT, pagefile,
  hibernation/crash dumps/clipboard/scrollback гарантированно не стираются.

## Не исправленные границы и остаточные риски

1. **Нет защиты от hostile host или supply-chain компрометации.** Hash pins находятся
   рядом с кодом; можно подменить оба. Уже загруженные типы/модули и процесс PowerShell
   считаются доверенными. Проверка System32/imports не ловит все dynamic loads/preload.
   Подпись LibreWolf EXE не удостоверяет ZIP/все DLL; GitHub digest не независимая подпись.
2. **Нет anti-rollback.** Старый валидный vault/backup можно подставить, и AEAD примет его.
   Encrypted backups содержат старые credentials; смена пароля/отзыв не реализованы.
3. **File.Replace не полный recovery-протокол.** Flush(true)+read-back и два hash-check
   защищают от ряда обычных ошибок, но не от power-loss/disk-full/unplug и враждебной
   гонки между hash и Replace. Нет delete-then-move fallback; при ошибке публикации
   проверять active/backup отдельно. Зависит от filesystem, на NTFS пользователя synthetic PASS.
4. **Local SOCKS не изолирован по пользователю/процессу.** Другие локальные программы
   могут использовать loopback listener. Browser fail-closed — не Windows kill switch.
   Проверенный proxy error не доказывает отсутствие всех каналов утечки/будущих регрессий.
5. **Старые plaintext/legacy menu остаются обходом.** Browser profile/downloads не
   зашифрованы. Нет безопасного SSD erase или защиты всего хоста. Не мигрировать/не удалять.
6. **Парсер ограниченный, не универсальный.** Неподдержанные записи пропускаются;
   native -test обязателен. Policy не является полноценной JSON-schema/type verifier:
   часть scalar coercion, duplicate JSON semantics и hostnames контролирует также Xray.
   Не обещать безопасную загрузку произвольных конфигов. Нет hostile-input fuzz matrix.
7. **Refresh сохраняет только activeConfig.** Полный список nodes/selection schema,
   atomic updater UI и устойчивые идентификаторы при изменении полей сервером не завершены.
8. **Fetch идёт через Windows network/system proxy**, с v2rayNG UA и сохранённым x-hwid,
   не через управляемый tunnel. Redirect запрещён, response size/deadlines ограничены.
   Это не обещание скрыть сам факт запроса от сети/провайдера; default fetch в новом
   refresh core пока не проверен живым провайдером. Сам старый fetch использовался ранее.

## Решение
После повторных transport+synthetic refresh тестов допустим контролируемый live refresh
отдельного WorkingRuntime с тем же паролем, без миграции, без удаления старых файлов.
Перед первым реальным обновлением ещё раз закрыть браузер/сессию. После success отдельно
проверить ValidateOnly и соединение. При error не перезапускать blindly и не удалять backup.
Не называть это «дыр нет» или «вся установка зашифрована».
