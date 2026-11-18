# Что изменено в secret.ps1

Разбор вёлся навыками из библиотеки: `crypto-engineering/zeroize-audit`, `crypto-engineering/sharp-edges` (включая `references/crypto-apis.md` и `references/lang-csharp.md`), `security-crypto/cryptographic-file-format-design`, `security-crypto/applied-cryptography-engineering`, `security-crypto/secure-key-derivation-and-management`, `crypto-engineering/implementing-aes-encryption-for-data-at-rest`.

Дополнительный вводный фактор: **сценарий использования — общий ПК в колледже.** Это не «добавить галочку», а смена модели угроз, поэтому часть правок касается не криптографии, а поведения на чужой машине.

Нумерация совпадает с отчётом ревью.

---

## CRITICAL

### C1. Открытый текст больше не попадает на флешку

**Было:**
```powershell
function Unprotect-KitFile([string]$EncPath, [string]$OutPath, [string]$Password) {
    ...
    [IO.File]::WriteAllBytes($OutPath, $plain)      # ← запись на носитель
    return $OutPath
}
```
и `Protect-KitFile` удалял исходник через `Remove-Item`, что на FAT32/exFAT не стирает данные.

**Стало:** добавлены две функции, работающие с памятью, — основной путь для флешки:

```powershell
function Protect-KitBytes([byte[]]$Plain, [string]$Password, [string]$Target, [string]$SourcePath = '', [switch]$KeepSource)
function Unprotect-KitBytes([string]$EncPath, [string]$Password)     # возвращает byte[]
```

`Unprotect-KitFile` / `Protect-KitFile` сохранены для совместимости, но переписаны как обёртки над `*Bytes` и в README помечены как непригодные для носителя. В шапке файла прямо описано, почему `Remove-Item` на флешке — не стирание.

### C2. Секреты в памяти зануляются

**Было:** `$all` (64 байта из PBKDF2), `$k.Enc`, `$k.Mac`, `$plain` (открытый текст) жили до сборки мусора.

**Стало:**
```powershell
function Clear-KitBytes([byte[]]$Buf) {
    if ($null -ne $Buf -and $Buf.Length -gt 0) { [Array]::Clear($Buf, 0, $Buf.Length) }
}
function Clear-KitKeys($Keys) { ... 'Enc' / 'Mac' / 'Check' ... }
```

Зануление добавлено в `finally` у: `Get-KitKeysRaw` (массив `$all` сразу после раскладки на ключи), `Protect-KitBytes` (ключи, `$enc`, `$both`), `Unprotect-KitBytes` (ключи, `$both`), `Set-KitPasswordValue` (ключи), `Test-KitPassword` (ключи), `Protect-KitFile` (через `Protect-KitBytes`), `Update-KitContainer` (открытый текст после перешифровки).

Проверяется тестом: `Check 'Clear-KitBytes зануляет массив'`.

### C3. Пароль не возвращается из функций

**Было:**
```powershell
function Set-KitPassword([string]$Vpn) {
    ...
    return $p1        # пароль уезжает вызывающему как [string]
}
```

**Стало:** `return $true` / `return $null`. Пароль остаётся локальным. Плюс `Set-StrictMode -Version 2.0` и глобальный `$ErrorActionPreference = 'Stop'` из скрипта **убраны** — они меняли поведение вызывающей сессии при dot-sourcing.

Полное избавление от `[string]` для пароля невозможно в PowerShell 5.1 (PBKDF2 принимает строку), и это прямо написано в README, а не замаскировано.

---

## HIGH

### H4. Заголовок контейнера аутентифицирован (AAD)

**Было:** `$mac = Get-KitHmac $k.Mac ($iv + $enc)` — `iters`, `prf`, `salt` не покрывались. Подмена `iters` на 2 000 000 давала DoS, а не обнаружение.

**Стало:**
```powershell
function Get-KitAad($Meta, [byte[]]$Iv) {
    $parts = @($script:KitEncHead, "iters=$($Meta['iters'])", "prf=$($Meta['prf'])",
               "salt=$($Meta['salt'])", "iv=$([Convert]::ToBase64String($Iv))")
    return ,([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))
}
```
MAC теперь считается по `AAD || iv || ciphertext` и в `Protect-KitBytes`, и в `Unprotect-KitBytes`.

Это смена формата → `kit-enc/2`. Старые файлы читаются по ветке `$p.Legacy`. Тесты: `'MAC с AAD совпал с Python'`, `'подмена iters обнаружена (AAD)'`, `'подмена salt обнаружена (AAD)'`.

### H5. Разделение доменов ключей

**Было:** 64 байта, проверочный HMAC считался **тем же** MAC-ключом.

**Стало:** 96 байт — `enc | mac | check`, у каждого своё назначение:
```powershell
if ($Len -ge 96) { $chk = New-Object byte[] 32; [Array]::Copy($all, 64, $chk, 0, 32); $res['Check'] = $chk }
```
`secret.dat` получил заголовок `kit-secret/2` и доменную строку `kit-secret-check/2` (было `kit-secret-check`). Для v1 сохранён старый путь: `$k.Mac` + `kit-secret-check`.

### H6. Пароль проверяется в обеих операциях шифрования

**Было:** `Protect-KitFile -Password ''` шифровал пустым паролем молча.

**Стало:** `if ("$Password".Length -lt $script:KitMinPassword) { throw ... }` в `Protect-KitFile` и `Protect-KitBytes`; `if ("$Password".Length -lt 1) { return $null }` в `Unprotect-KitBytes`. Тест: `'пустой пароль в Protect отвергнут'`.

### H7. `Read-KitYesNo`: Enter больше не значит «да»

**Было:** `if ($buf -eq '') { return $true }`.

**Стало:** Enter, Esc, таймаут и отсутствие консоли — все возвращают `$false`. `y`/`Y` — `$true`, `n`/`N` — `$false`, ответ срабатывает по одной клавише. Убраны кириллические `д`/`н`, чтобы не путать раскладкой на чужой машине.

### H8. CBC оставлен осознанно, с обоснованием в коде

`AesGcm` есть только в .NET Core 3.0+ — то есть **недоступен в Windows PowerShell 5.1**, а на учебных ПК именно 5.1. Это записано в шапке файла первым абзацем, а не спрятано. Композиция EtM сохранена и проверена тестами; порядок «MAC → AES» зафиксирован в коде комментарием.

---

## MEDIUM

**M9. `[Console]::ReadKey` в `Read-KitMasked` обёрнут в try/catch** — в ISE и embedding-хостах больше нет падения. `Set-KitPassword` дополнительно ловит исключение и возвращает `$null`.

**M10. Убран бесконечный цикл.** `if (-not [Console]::KeyAvailable)` теперь внутри `try` — при отсутствии консоли функция возвращает `''`, а не крутится.

**M11. `ICryptoTransform` освобождается:** `$ic = $aes.CreateEncryptor()` / `CreateDecryptor()` + `$ic.Dispose()` в `finally`, в обеих функциях.

**M12. Проверка размера до KDF:** `Get-Item` + сравнение с `$script:KitMaxFileSize` вынесены в начало `Protect-KitFile`, до `ReadAllBytes` и до PBKDF2.

**M13. Легаси не проходит молча:** `Get-KitParams` возвращает `Legacy = $true`, и `Update-KitContainer` / `Update-KitSecret` переводят файл в v2. Тест: `'Upgrade перешифровал v1 в v2'`.

**M14. Длина пароля не видна:** звёздочки группами по 4, остаток добивается маркерами, а не пробелом.

---

## LOW

| Было | Стало |
| --- | --- |
| Комментарий «сравнивается за постоянное время» без оговорок | «Гарантии по времени PowerShell не даёт, но раннего выхода по первому несовпадению нет» |
| Только TOCTOU-проверка размера | Размер проверяется до чтения; остаточная гонка отмечена в README как известное ограничение |
| `New-KitRandom` без валидации | `if ($Len -le 0 -or $Len -gt 1048576) { throw ... }` |
| `$deadline`, `$buf`, `$plain` местами не использовались | Мёртвый `$buf` удалён, остальные используются |
| Дубли ключей в заголовке: последний выигрывал | `if ($h.ContainsKey($k)) { return $null }` — отказ целиком |
| Регекс ключа `^([A-Za-z0-9_]+)=` | `^([A-Za-z][A-Za-z0-9_]*)=` — ключ не может начинаться с цифры |
| `Get-KitKeys` содержал мёртвую строку с тернарником в `if` | Упрощено до двух `return` |
| Лимит base64 не проверялся | `if ($S.Length -gt 46603378) { return $null }` |

---

## Что НЕ менялось (и почему)

- **AES-256-CBC + HMAC-SHA256** — см. H8. Переход на GCM сломал бы совместимость с 5.1.
- **600 000 итераций PBKDF2-SHA256** — адекватно для 2026 для пароля-фразы; вынесено в `$script:KitSecretIters`.
- **Порядок MAC → расшифровка**, **свежие salt/iv на файл**, **fail-closed во всех ветках** — это было сделано правильно изначально.
- **Отказ при перенаправленном вводе** — оставлено, это верное поведение.

---

## Добавлено в этой версии

- `Show-KitThreatModel` — печатает, от чего защита есть и чего нет. Полезно именно на общей машине.
- `Clear-KitBytes`, `Clear-KitKeys` — зануление.
- `Get-KitAad` — единое место формирования AAD.
- `Get-KitParams` — разбор и валидация `iters`/`prf` в одном месте.
- `Get-KitKeysRaw` — явная длина ключевого материала, чтобы v1 (64) и v2 (96) не путались.
- `Protect-KitBytes`, `Unprotect-KitBytes` — путь без записи на носитель.
- `Update-KitContainer`, `Update-KitSecret` — миграция v1 → v2.
- `Test-KitPasswordStrength` — вынесено из `Set-KitPassword`, возвращает причину слабости.
- `tools/kit-secret/tests/test-kit-secret.ps1` — 33 проверки с независимыми эталонами.

---

## Проверка отчёта

Этот файл — обязательство: каждый пункт выше соответствует конкретному месту в `secret.ps1`. Сверка делается так:

```bash
grep -n "Clear-KitBytes\|Get-KitAad\|Protect-KitBytes\|Unprotect-KitBytes\|Update-Kit" secret.ps1
grep -n "Legacy\|KitSecretHead1\|KitEncHead1" secret.ps1
grep -n "KitMinPassword" secret.ps1
```

Тесты проверяют поведение, а не наличие строк:
- AAD и MAC сверяются с эталоном из независимой реализации;
- подмена `iters` и `salt` должна **провалить** расшифровку;
- `kit-enc/1` должен читаться, `Update-KitContainer` должен дать `kit-enc/2`, после чего файл остаётся читаемым.

**Ограничение:** тесты не запускались в этой среде — PowerShell недоступен. См. README, раздел «Что осталось непроверенным».
