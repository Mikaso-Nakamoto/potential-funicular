# test-kit-secret.ps1 — самопроверка secret.ps1.
#
# Запуск:  powershell -NoProfile -ExecutionPolicy Bypass -File .\test-kit-secret.ps1
#      или pwsh -NoProfile -File ./test-kit-secret.ps1
#
# Векторы ниже посчитаны независимо (Python: hashlib.pbkdf2_hmac + pycryptodome
# AES-CBC), поэтому тест ловит не «мой код совпал сам с собой», а реальное
# расхождение с эталонной реализацией PBKDF2/HMAC/AES.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'secret.ps1')

$script:Fail = 0
$script:Pass = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) {
        $script:Pass++
        Write-Host ("  PASS  " + $Name) -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host ("  FAIL  " + $Name + $(if ($Detail) { "  -> $Detail" } else { '' })) -ForegroundColor Red
    }
}

Write-Host '=== 1. Эталонные векторы PBKDF2 / HMAC ===' -ForegroundColor Cyan
$pw   = 'правильный-конь-батарея-7'
$salt = [byte[]](0..15)
$k    = Get-KitKeys $pw $salt 600000 'SHA256'
$encHex = -join ($k.Enc   | ForEach-Object { $_.ToString('x2') })
$macHex = -join ($k.Mac   | ForEach-Object { $_.ToString('x2') })
$chkHex = -join ($k.Check | ForEach-Object { $_.ToString('x2') })
Check 'enc-ключ совпал с Python'   ($encHex -eq '091991bd05e689fc5d1f966347824a1affff80811cd0f9ea917193d85d47b290') $encHex
Check 'mac-ключ совпал с Python'   ($macHex -eq '01b591cc6e99ab929a7cb366e59b9e6b45e5d5347e2164f75e8b0cb0d928ed51') $macHex
Check 'check-ключ совпал с Python' ($chkHex -eq 'e5f65a14549f9c914f61074cb09ee1e3c790f1bcbc050fe1afc33b9bb6424286') $chkHex
Check 'ключи разделены (enc != mac != check)' ($encHex -ne $macHex -and $macHex -ne $chkHex -and $encHex -ne $chkHex)
Clear-KitKeys $k

Write-Host '=== 2. AES-256-CBC: шифртекст совпал с эталоном ===' -ForegroundColor Cyan
$iv = [byte[]](16..31)
$plainBytes = [Text.Encoding]::UTF8.GetBytes('vless://uuid@host:443?type=ws#node')
$k2 = Get-KitKeys $pw $salt 600000 'SHA256'
$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.KeySize = 256
$aes.Key = $k2.Enc; $aes.IV = $iv
$ict = $aes.CreateEncryptor()
$ct = $ict.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
$ict.Dispose(); $aes.Dispose()
$ctB64 = [Convert]::ToBase64String($ct)
Check 'шифртекст совпал с Python' ($ctB64 -eq 'kZDcsA878VPvReEWyNWs9XHZWoXEDpyLNTmY1d2thib9f3f1HdJ1U2TIHyOxTzYo') $ctB64

Write-Host '=== 3. Полная проверка контейнера kit-enc/2 (AAD) ===' -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('kittest-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # Собираем контейнер вручную по эталонным значениям и проверяем, что наш
    # Unprotect его принимает — это проверяет формат AAD целиком.
    $metaHand = @{
        _head = 'kit-enc/2'; iters = '600000'; prf = 'SHA256'
        salt = [Convert]::ToBase64String($salt); iv = [Convert]::ToBase64String($iv)
    }
    $aad = Get-KitAad $metaHand $iv
    $both = New-Object byte[] ($aad.Length + $iv.Length + $ct.Length)
    [Array]::Copy($aad, 0, $both, 0, $aad.Length)
    [Array]::Copy($iv, 0, $both, $aad.Length, $iv.Length)
    [Array]::Copy($ct, 0, $both, $aad.Length + $iv.Length, $ct.Length)
    $mac = Get-KitHmac $k2.Mac $both
    $macHex2 = -join ($mac | ForEach-Object { $_.ToString('x2') })
    Check 'MAC с AAD совпал с Python' ($macHex2 -eq '8a0e3f652b397e1a13ddad5c9b1068e70febac2bc3e095ef42ecb6c20493e10d') $macHex2
    Clear-KitKeys $k2

    $lines = @(
        'kit-enc/2', 'iters=600000', 'prf=SHA256',
        'salt=' + $metaHand['salt'], 'iv=' + $metaHand['iv'],
        'mac=' + [Convert]::ToBase64String($mac), 'data=' + $ctB64
    )
    $goodPath = Join-Path $tmp 'good.enc'
    [IO.File]::WriteAllText($goodPath, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

    $back = Unprotect-KitBytes -EncPath $goodPath -Password $pw
    Check 'расшифровка эталонного контейнера' ($null -ne $back -and [Text.Encoding]::UTF8.GetString($back) -eq 'vless://uuid@host:443?type=ws#node')
    if ($back) { Clear-KitBytes $back }

    Check 'неверный пароль отвергнут' ($null -eq (Unprotect-KitBytes -EncPath $goodPath -Password 'совсем-другой-пароль'))

    # Подмена заголовка: iters изменён — MAC обязан не сойтись.
    $badLines = $lines.Clone()
    $badLines[1] = 'iters=500000'
    $badPath = Join-Path $tmp 'tampered.enc'
    [IO.File]::WriteAllText($badPath, (($badLines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    Check 'подмена iters обнаружена (AAD)' ($null -eq (Unprotect-KitBytes -EncPath $badPath -Password $pw))

    # Подмена соли — тоже.
    $bad2 = $lines.Clone()
    $bad2[3] = 'salt=' + [Convert]::ToBase64String((New-Object byte[] 16))
    $bad2Path = Join-Path $tmp 'tampered2.enc'
    [IO.File]::WriteAllText($bad2Path, (($bad2 -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    Check 'подмена salt обнаружена (AAD)' ($null -eq (Unprotect-KitBytes -EncPath $bad2Path -Password $pw))

    Write-Host '=== 4. Круговой тест Protect/Unprotect ===' -ForegroundColor Cyan
    $src = Join-Path $tmp 'payload.bin'
    $payload = [Text.Encoding]::UTF8.GetBytes('{"uuid":"11111111-2222-3333-4444-555555555555"}')
    [IO.File]::WriteAllBytes($src, $payload)
    $encPath = Protect-KitFile -Path $src -Password $pw -KeepSource
    Check 'Protect создал .enc' (Test-Path -LiteralPath $encPath)
    $rt = Unprotect-KitBytes -EncPath $encPath -Password $pw
    Check 'круговое шифрование сохранило данные' ($null -ne $rt -and [Text.Encoding]::UTF8.GetString($rt) -eq '{"uuid":"11111111-2222-3333-4444-555555555555"}')
    if ($rt) { Clear-KitBytes $rt }
    Check 'в контейнере нет открытого текста' (-not ([IO.File]::ReadAllText($encPath) -match '11111111'))

    Write-Host '=== 5. Проверка пароля и secret.dat ===' -ForegroundColor Cyan
    $vpn = Join-Path $tmp 'vpn'
    Set-KitPasswordValue -Vpn $vpn -Password $pw
    $sec = [IO.File]::ReadAllText((Join-Path $vpn 'secret.dat'))
    Check 'secret.dat имеет заголовок kit-secret/2' ($sec -match 'kit-secret/2')
    Check 'secret.dat не содержит пароль' (-not ($sec -match [regex]::Escape($pw)))
    Check 'верный пароль принят'  (Test-KitPassword -Vpn $vpn -Password $pw)
    Check 'неверный пароль отвергнут' (-not (Test-KitPassword -Vpn $vpn -Password 'неверный-пароль-123'))

    Write-Host '=== 6. Защитные проверки ===' -ForegroundColor Cyan
    $threw = $false
    try { Protect-KitBytes -Plain ([byte[]](1..20)) -Password '' -Target (Join-Path $tmp 'x.enc') } catch { $threw = $true }
    Check 'пустой пароль в Protect отвергнут' $threw

    $threw = $false
    try { Set-KitPasswordValue -Vpn $vpn -Password 'коротко' } catch { $threw = $true }
    Check 'короткий пароль отвергнут' $threw

    # Контейнер с дублем ключа — fail-closed.
    $dupPath = Join-Path $tmp 'dup.enc'
    $dup = @('kit-enc/2','iters=600000','iters=600000','prf=SHA256','salt=' + $metaHand['salt'])
    [IO.File]::WriteAllText($dupPath, (($dup -join "`n") + "`n"))
    Check 'дубль ключа в заголовке отвергнут' ($null -eq (Read-KitHeaders $dupPath))

    # Мусорный iters — fail-closed.
    $badIters = @('kit-enc/2','iters=99','prf=SHA256','salt=' + $metaHand['salt'])
    $biPath = Join-Path $tmp 'bi.enc'
    [IO.File]::WriteAllText($biPath, (($badIters -join "`n") + "`n"))
    Check 'iters вне диапазона отвергнут' ($null -eq (Unprotect-KitBytes -EncPath $biPath -Password $pw))

    Check 'Clear-KitBytes зануляет массив' ((& { $b = [byte[]](1..8); Clear-KitBytes $b; ($b | Measure-Object -Sum).Sum -eq 0 }))

    Write-Host '=== 7. Обратная совместимость с kit-enc/1 ===' -ForegroundColor Cyan
    # Эталон v1 посчитан отдельно: PBKDF2 на 64 байта, MAC по iv+шифртекст,
    # заголовок НЕ покрыт. Если код перестанет читать такие файлы — тест упадёт.
    $k1 = Get-KitKeysRaw $pw $salt 600000 64 'SHA256'
    $bothV1 = New-Object byte[] ($iv.Length + $ct.Length)
    [Array]::Copy($iv, 0, $bothV1, 0, $iv.Length)
    [Array]::Copy($ct, 0, $bothV1, $iv.Length, $ct.Length)
    $macV1 = Get-KitHmac $k1.Mac $bothV1
    $macV1Hex = -join ($macV1 | ForEach-Object { $_.ToString('x2') })
    Check 'MAC v1 совпал с Python' ($macV1Hex -eq 'e8b9763b793bd0db1d7b822bf8386ad0125f824dcd30aa17a5ad9d094f0f1639') $macV1Hex
    Clear-KitKeys $k1
    Clear-KitBytes $bothV1

    $v1lines = @(
        'kit-enc/1', 'iters=600000', 'prf=SHA256',
        'salt=' + [Convert]::ToBase64String($salt), 'iv=' + [Convert]::ToBase64String($iv),
        'mac=' + [Convert]::ToBase64String($macV1), 'data=' + $ctB64
    )
    $v1Path = Join-Path $tmp 'legacy.enc'
    [IO.File]::WriteAllText($v1Path, (($v1lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    $backV1 = Unprotect-KitBytes -EncPath $v1Path -Password $pw
    Check 'старый контейнер v1 читается' ($null -ne $backV1 -and [Text.Encoding]::UTF8.GetString($backV1) -eq 'vless://uuid@host:443?type=ws#node')
    if ($backV1) { Clear-KitBytes $backV1 }

    # v1 без поля prf — это SHA1 (поведение старого Rfc2898DeriveBytes).
    $k1sha1 = Get-KitKeysRaw $pw $salt 600000 64 'SHA1'
    $bothS = New-Object byte[] ($iv.Length + $ct.Length)
    [Array]::Copy($iv, 0, $bothS, 0, $iv.Length)
    [Array]::Copy($ct, 0, $bothS, $iv.Length, $ct.Length)
    $macS = Get-KitHmac $k1sha1.Mac $bothS
    Clear-KitKeys $k1sha1
    Clear-KitBytes $bothS
    $noPrf = @(
        'kit-enc/1', 'iters=600000',
        'salt=' + [Convert]::ToBase64String($salt), 'iv=' + [Convert]::ToBase64String($iv),
        'mac=' + [Convert]::ToBase64String($macS), 'data=' + $ctB64
    )
    $npPath = Join-Path $tmp 'legacy-noprf.enc'
    [IO.File]::WriteAllText($npPath, (($noPrf -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    Check 'v1 без prf трактуется как SHA1' ($null -ne (Unprotect-KitBytes -EncPath $npPath -Password $pw))

    # -Upgrade переводит v1 в v2 и v2 остаётся читаемым.
    $upg = Update-KitContainer -EncPath $v1Path -Password $pw
    Check 'Upgrade перешифровал v1 в v2' ($upg -and ((Read-KitHeaders $v1Path)['_head'] -eq 'kit-enc/2'))
    $afterUp = Unprotect-KitBytes -EncPath $v1Path -Password $pw
    Check 'после Upgrade данные читаются' ($null -ne $afterUp -and [Text.Encoding]::UTF8.GetString($afterUp) -eq 'vless://uuid@host:443?type=ws#node')
    if ($afterUp) { Clear-KitBytes $afterUp }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("ИТОГО: прошло $($script:Pass), провалено $($script:Fail)") -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) { exit 1 }
