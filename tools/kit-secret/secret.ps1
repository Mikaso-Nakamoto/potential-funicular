# secret.ps1 — парольная защита ключей на флешке.
#
# Совместимость: Windows PowerShell 5.1 (.NET Framework 4.7.2+) и PowerShell 7+.
# AES-GCM здесь НЕ используется намеренно: System.Security.Cryptography.AesGcm
# появился только в .NET Core 3.0 и недоступен в 5.1, а на учебных ПК стоит
# именно встроенный 5.1. Поэтому Encrypt-then-MAC на AES-256-CBC + HMAC-SHA256.
#
# ─────────────────────────────────────────────────────────────────────────────
# МОДЕЛЬ УГРОЗ: флешка + ЧУЖОЙ ПК (компьютерный класс, общая машина)
# ─────────────────────────────────────────────────────────────────────────────
# Защищаем: vpn\config.json (UUID узлов) и vpn\sub.txt (URL подписки с токеном).
# Считаем, что на машине может работать кто-то ещё и у него может быть доступ
# к тому же диску.
#
# От чего защищает:
#   • Потеря/кража флешки без знания пароля.
#   • Чтение файлов другим пользователем машины после выхода.
#   • Горизонтальное перемещение по файловой системе: открытый текст на флешку
#     НЕ пишется вообще, только в память.
#   • Параметры KDF и IV привязаны к MAC, поэтому подмена заголовка ломает файл,
#     а не превращается в «медленное чтение».
#
# От чего НЕ защищает — важно понимать:
#   • Администратор или вредоносный процесс на машине во время работы скрипта:
#     он может читать память процесса, нажатия клавиш и подменять наш код.
#     Против этого нужна доверенная машина, а не скрипт.
#   • Флешка exFAT/FAT32 не умеет безопасно удалять: старое содержимое может
#     оставаться в свободных кластерах. Поэтому мы никогда не пишем туда
#     открытый текст — см. выше. Существующие незашифрованные файлы, которые
#     были на флешке ДО первого запуска, этим скриптом не «стираются»: их нужно
#     перезаписать на чистой машине или отформатировать флешку.
#   • Имена файлов, размеры, время изменения — не скрываются.
#   • Пароль, набранный на чужой клавиатуре, может быть перехвачен хардварно.
#
# Контейнеры:
#   vpn\secret.dat    kit-secret/2: iters, prf, salt, check(verifier). Пароль не хранится.
#   vpn\*.enc         kit-enc/2:    iters, prf, salt, iv, mac, data. MAC покрывает
#                                   заголовок целиком (AAD) + iv + шифртекст.
# Обратная совместимость: kit-secret/1 и kit-enc/1 читаются (без AAD, 64 байта
# ключа, PRF по умолчанию SHA1) и перешифровываются при -Upgrade.
#
# Забыли пароль — расшифровать нельзя, ключи считаются потерянными:
# дома заново ввести ссылки (пункт 4) и перевыпустить подписку (пункт 3).

# Скрипт рассчитан на dot-sourcing или точечный вызов функций: он НЕ трогает
# глобальные Set-StrictMode и $ErrorActionPreference, чтобы не менять поведение
# вызывающей сессии. Все опасные места обрабатываются локально через try/catch
# и -ErrorAction Stop.

$script:KitSecretIters = 600000
$script:KitSecretHead  = 'kit-secret/2'
$script:KitSecretHead1 = 'kit-secret/1'
$script:KitEncHead     = 'kit-enc/2'
$script:KitEncHead1    = 'kit-enc/1'
$script:KitSecretCheck = 'kit-secret-check/2'
$script:KitSecretChk1  = 'kit-secret-check'
$script:KitMaxInBytes  = 33554432   # 32 МиБ — предел для чтения контейнера
$script:KitMaxFileSize = 16777216   # 16 МиБ — предел для исходного файла
$script:KitMaxIters    = 2000000
$script:KitMinIters    = 1000
$script:KitMinPassword = 10

# ── Ключи и память ──────────────────────────────────────────────────────────

function New-KitRandom([int]$Len) {
    if ($Len -le 0 -or $Len -gt 1048576) { throw "Недопустимый размер случайных данных: $Len" }
    $b = New-Object byte[] $Len
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ,$b
}

function Clear-KitBytes([byte[]]$Buf) {
    # Зануление секретов в управляемой памяти. Не панацея (GC мог успеть
    # скопировать массив), но убирает самый долгий след — до сборки мусора.
    if ($null -ne $Buf -and $Buf.Length -gt 0) {
        [Array]::Clear($Buf, 0, $Buf.Length)
    }
}

function Clear-KitKeys($Keys) {
    if ($null -eq $Keys) { return }
    if ($Keys.ContainsKey('Enc')) { Clear-KitBytes $Keys.Enc }
    if ($Keys.ContainsKey('Mac')) { Clear-KitBytes $Keys.Mac }
    if ($Keys.ContainsKey('Check')) { Clear-KitBytes $Keys.Check }
}

function Invoke-KitPbkdf2([string]$Password, [byte[]]$Salt, [int]$Iters, [int]$Len = 96, [string]$Prf = 'SHA256') {
    # Старые контейнеры без поля prf: Rfc2898DeriveBytes по умолчанию HMAC-SHA1.
    switch ($Prf.ToUpperInvariant()) {
        'SHA1'   { $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $Salt, $Iters) }
        'SHA256' { $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Password, $Salt, $Iters, [System.Security.Cryptography.HashAlgorithmName]::SHA256) }
        default  { throw "Неподдерживаемый PBKDF2 PRF: $Prf" }
    }
    try { return ,$kdf.GetBytes($Len) } finally { $kdf.Dispose() }
}

function Get-KitKeys([string]$Password, [byte[]]$Salt, [int]$Iters, [string]$Prf = 'SHA256') {
    # v2 — 96 байт (Enc 32 | Mac 32 | Check 32): три независимых ключа из одного
    # PBKDF2, то есть разделение доменов.
    # v1 — 64 байта (Enc 32 | Mac 32): проверочный HMAC считался тем же Mac-ключом.
    if ($Prf -eq 'SHA1') { return (Get-KitKeysRaw $Password $Salt $Iters 64 $Prf) }
    return (Get-KitKeysRaw $Password $Salt $Iters 96 $Prf)
}

function Get-KitKeysRaw([string]$Password, [byte[]]$Salt, [int]$Iters, [int]$Len, [string]$Prf) {
    $all = Invoke-KitPbkdf2 $Password $Salt $Iters $Len $Prf
    try {
        $enc = New-Object byte[] 32
        $mac = New-Object byte[] 32
        [Array]::Copy($all, 0, $enc, 0, 32)
        [Array]::Copy($all, 32, $mac, 0, 32)
        $res = @{ Enc = $enc; Mac = $mac }
        if ($Len -ge 96) {
            $chk = New-Object byte[] 32
            [Array]::Copy($all, 64, $chk, 0, 32)
            $res['Check'] = $chk
        }
        return $res
    } finally {
        Clear-KitBytes $all
    }
}

function Get-KitHmac([byte[]]$Key, [byte[]]$Data) {
    $h = New-Object System.Security.Cryptography.HMACSHA256(, $Key)
    try { return ,$h.ComputeHash($Data) } finally { $h.Dispose() }
}

function Test-KitMac([byte[]]$A, [byte[]]$B) {
    # Сравнение без ранних выходов. Гарантии по времени PowerShell не даёт,
    # но раннего выхода по первому несовпадению здесь нет.
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne $B.Length) { return $false }
    $d = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ($A[$i] -bxor $B[$i]) }
    return ($d -eq 0)
}

# ── Разбор контейнера ───────────────────────────────────────────────────────

function Read-KitHeaders([string]$Path) {
    # key=value построчно; первая строка — заголовок формата.
    # Всё, что не похоже на наш контейнер, возвращает $null (fail-closed).
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        # Проверка размера ДО чтения: не даём аллоцировать по воле файла.
        if ($fi.Length -le 0 -or $fi.Length -gt $script:KitMaxInBytes) { return $null }
        $lines = [IO.File]::ReadAllLines($Path)
    } catch { return $null }
    if ($null -eq $lines -or $lines.Count -lt 1) { return $null }
    $h = @{ _head = "$($lines[0])".Trim() }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^([A-Za-z][A-Za-z0-9_]*)=(.*)$') {
            $k = $Matches[1]
            if ($h.ContainsKey($k)) { return $null }   # дубль ключа — признак подмены
            $h[$k] = $Matches[2].Trim()
        }
    }
    return $h
}

function ConvertFrom-KitB64([string]$S) {
    if (-not $S) { return $null }
    if ($S.Length -gt 46603378) { return $null }        # ~35 МиБ base64
    try { return ,[Convert]::FromBase64String($S) } catch { return $null }
}

function Get-KitParams($Meta, [string]$HeadV2, [string]$HeadV1) {
    # Достаёт iters/prf из заголовка и проверяет диапазон. $null при любой аномалии.
    $iters = 0
    if (-not [int]::TryParse("$($Meta['iters'])", [ref]$iters)) { return $null }
    if ($iters -lt $script:KitMinIters -or $iters -gt $script:KitMaxIters) { return $null }
    $prf = ''
    if ($Meta.ContainsKey('prf')) { $prf = "$($Meta['prf'])" }
    $legacy = ($Meta['_head'] -eq $HeadV1)
    if (-not $prf) { $prf = 'SHA1' }
    if ($prf -notin @('SHA1', 'SHA256')) { return $null }
    if (-not $legacy -and $prf -eq 'SHA1') { return $null }   # v2 с SHA1 не выпускаем
    return @{ Iters = $iters; Prf = $prf; Legacy = $legacy }
}

function Get-KitAad($Meta, [byte[]]$Iv) {
    # AAD = заголовок целиком без mac и data. Любая правка iters/prf/salt/iv
    # меняет MAC, то есть подмена заголовка обнаруживается, а не просто ломает ключ.
    $b64 = [Convert]::ToBase64String($Iv)
    $parts = @(
        $script:KitEncHead
        "iters=$($Meta['iters'])"
        "prf=$($Meta['prf'])"
        "salt=$($Meta['salt'])"
        "iv=$b64"
    )
    return ,([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))
}

# ── Пароль ──────────────────────────────────────────────────────────────────

function Get-KitSecretFile([string]$Vpn) { Join-Path $Vpn 'secret.dat' }
function Test-KitSecret([string]$Vpn) { Test-Path -LiteralPath (Get-KitSecretFile $Vpn) }

function Read-KitMasked([string]$Prompt) {
    # Ввод звёздочками: Read-Host -AsSecureString не показывает вообще ничего.
    # В общем классе важно видеть, что клавиша нажалась, и уметь стереть.
    if ($Prompt) { Write-Host ($Prompt + ' ') -ForegroundColor Gray -NoNewline }
    $sb = New-Object System.Text.StringBuilder
    try {
        if ([Console]::IsInputRedirected) { return '' }
    } catch { return '' }
    while ($true) {
        try {
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 30; continue }
            $k = [Console]::ReadKey($true)
        } catch {
            # Нет консоли (ISE, embedding, service host) — не зацикливаемся.
            Write-Host ''
            return ''
        }
        if ($k.Key -eq 'Enter') { Write-Host ''; break }
        if ($k.Key -eq 'Escape') {
            [void]$sb.Clear()
            Write-Host ''
            return ''
        }
        if ($k.Key -eq 'Backspace') {
            if ($sb.Length -gt 0) {
                [void]$sb.Remove($sb.Length - 1, 1)
                Write-Host "`b `b" -NoNewline
            }
            continue
        }
        $c = $k.KeyChar
        if ([char]::IsControl($c)) { continue }
        [void]$sb.Append($c)
        # Печатаем один '*' на каждые 4 символа, остаток дополняем при Enter:
        # точная длина пароля на общей машине — тоже информация.
        if (($sb.Length % 4) -eq 0) { Write-Host '*' -NoNewline }
    }
    # Добиваем маркеры до кратности 4, чтобы не выдавать остаток длины.
    $pad = $sb.Length % 4
    if ($pad -ne 0) { for ($i = $pad; $i -lt 4; $i++) { Write-Host '*' -NoNewline } }
    $r = $sb.ToString()
    [void]$sb.Clear()
    return $r
}

function ConvertFrom-Secure([System.Security.SecureString]$S) {
    if ($null -eq $S) { return '' }
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($S)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Test-KitPasswordStrength([string]$P) {
    # Возвращает @{ Weak = $bool; Reason = '...' }
    if ($P.Length -lt $script:KitMinPassword) { return @{ Weak = $true; Reason = 'короче 10 символов' } }
    if ($P -match '^\d+$') { return @{ Weak = $true; Reason = 'только цифры' } }
    if ($P -match '(?i)^(qwerty|password|пароль|123456|admin|iloveyou|moscow|москва)') { return @{ Weak = $true; Reason = 'типовое слово' } }
    if ($P -match '^\p{L}{3,}\d{2,6}$') { return @{ Weak = $true; Reason = 'одно слово и цифры' } }
    if ($P -match '^(.)\1{4,}$') { return @{ Weak = $true; Reason = 'повтор одного символа' } }
    if ($P -match '^(0123|1234|2345|3456|4567|5678|6789)') { return @{ Weak = $true; Reason = 'последовательность' } }
    if ($P.Length -lt 12) { return @{ Weak = $true; Reason = 'короче 12 символов' } }
    return @{ Weak = $false; Reason = '' }
}

function Set-KitPasswordValue([string]$Vpn, [string]$Password) {
    # Неинтерактивно: записать secret.dat. Нужно для тестов и для смены пароля.
    if ("$Password".Length -lt $script:KitMinPassword) { throw "Пароль короче $($script:KitMinPassword) символов." }
    New-Item -ItemType Directory -Force -Path $Vpn | Out-Null
    $salt = New-KitRandom 16
    $k = $null
    try {
        $k = Get-KitKeys $Password $salt $script:KitSecretIters 'SHA256'
        $check = Get-KitHmac $k.Check ([Text.Encoding]::UTF8.GetBytes($script:KitSecretCheck))
        $txt = @(
            $script:KitSecretHead
            "iters=$($script:KitSecretIters)"
            'prf=SHA256'
            'salt=' + [Convert]::ToBase64String($salt)
            'check=' + [Convert]::ToBase64String($check)
        ) -join "`n"
        [IO.File]::WriteAllText((Get-KitSecretFile $Vpn), $txt + "`n", (New-Object System.Text.UTF8Encoding $false))
    } finally {
        Clear-KitKeys $k
    }
}

function Set-KitPassword([string]$Vpn) {
    # Интерактивно: придумать пароль и записать secret.dat.
    # Возвращает $true при успехе и $null при отказе — сам пароль наружу не отдаём.
    if (Test-KitSecret $Vpn) { throw 'Пароль уже задан.' }
    while ($true) {
        Write-Host '[i] Пароль скрыт; Backspace — стереть, Esc — отмена.' -ForegroundColor DarkGray
        $p1 = ''
        try { $p1 = Read-KitMasked 'Придумай пароль (минимум 10 символов, лучше 4-5 слов):' }
        catch { Write-Host '[X] Ввод недоступен в этом хосте.' -ForegroundColor Red; return $null }
        if (-not $p1) { Write-Host '[i] Отменено.' -ForegroundColor Yellow; return $null }
        $st = Test-KitPasswordStrength $p1
        if ($st.Weak) {
            Write-Host "[!] Пароль слабый ($($st.Reason)): такой подбирают перебором." -ForegroundColor Yellow
            Write-Host '    Надёжнее — фраза из 4-5 случайных слов через дефис: «паром-улитка-стена-7».' -ForegroundColor DarkYellow
        }
        $p2 = ''
        try { $p2 = Read-KitMasked 'Повтори пароль ещё раз:' } catch { return $null }
        if ($p1 -ne $p2) { Write-Host '[!] Не совпало — ещё раз.' -ForegroundColor Red; continue }
        Set-KitPasswordValue $Vpn $p1
        Write-Host '[+] Пароль задан. Вводить его нужно при каждом подключении.' -ForegroundColor Green
        Write-Host '[i] Запиши пароль в надёжном месте: восстановить его нельзя.' -ForegroundColor Yellow
        return $true
    }
}

function Test-KitPassword([string]$Vpn, [string]$Password) {
    $meta = Read-KitHeaders (Get-KitSecretFile $Vpn)
    if (-not $meta) { return $false }
    $legacy = ($meta['_head'] -eq $script:KitSecretHead1)
    if (-not $legacy -and $meta['_head'] -ne $script:KitSecretHead) { return $false }
    $salt = ConvertFrom-KitB64 $meta['salt']
    $want = ConvertFrom-KitB64 $meta['check']
    if (-not $salt -or $salt.Length -ne 16) { return $false }
    if (-not $want -or $want.Length -ne 32) { return $false }
    $p = Get-KitParams $meta $script:KitSecretHead $script:KitSecretHead1
    if (-not $p) { return $false }

    $k = $null
    try {
        $k = Get-KitKeysRaw $Password $salt $p.Iters $(if ($p.Legacy) { 64 } else { 96 }) $p.Prf
        if ($p.Legacy) {
            $got = Get-KitHmac $k.Mac ([Text.Encoding]::UTF8.GetBytes($script:KitSecretChk1))
        } else {
            if (-not $k.ContainsKey('Check')) { return $false }
            $got = Get-KitHmac $k.Check ([Text.Encoding]::UTF8.GetBytes($script:KitSecretCheck))
        }
        return (Test-KitMac $got $want)
    } catch { return $false } finally { Clear-KitKeys $k }
}

function Read-KitPassword([string]$Vpn, [int]$Tries = 3) {
    # Спрашивает пароль до $Tries раз; '' при отказе (вызывающий решает, как падать).
    if (-not (Test-KitSecret $Vpn)) { return '' }
    try {
        if ([Console]::IsInputRedirected) {
            Write-Host '[X] Ключи зашифрованы паролем, а ввод перенаправлен — пароль ввести некуда.' -ForegroundColor Red
            return ''
        }
    } catch { return '' }
    Write-Host '[i] Пароль скрыт; Backspace — стереть, Esc — отмена.' -ForegroundColor DarkGray
    for ($i = 1; $i -le $Tries; $i++) {
        $p = ''
        try { $p = Read-KitMasked 'Пароль флешки:' } catch { return '' }
        if (-not $p) { Write-Host '[!] Пустой пароль.' -ForegroundColor Red; continue }
        if (Test-KitPassword $Vpn $p) { return $p }
        Write-Host "[!] Неверный пароль (попытка $i из $Tries)." -ForegroundColor Red
        if ($i -eq 1) {
            Write-Host '    Проверь раскладку (RU/EN) и Caps Lock: пароль вводится теми же' -ForegroundColor DarkYellow
            Write-Host '    символами, что и при задании. Кириллица и латиница не взаимозаменяемы.' -ForegroundColor DarkYellow
        }
    }
    return ''
}

# ── Шифрование файлов ───────────────────────────────────────────────────────

function Protect-KitFile([string]$Path, [string]$Password, [string]$Target = '', [switch]$KeepSource) {
    # Шифрует файл в <Path>.enc (или Target). Исходник удаляет, если не -KeepSource.
    # ВАЖНО: на флешке удаление не гарантирует стирания, поэтому вызывающая
    # сторона должна передавать уже прочитанные байты и не держать открытый
    # текст на носителе (см. Protect-KitBytes).
    if ("$Password".Length -lt $script:KitMinPassword) { throw "Пароль короче $($script:KitMinPassword) символов." }
    $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($fi.Length -gt $script:KitMaxFileSize) { throw 'Файл слишком большой для защищённого контейнера (лимит 16 МиБ).' }
    $plain = [IO.File]::ReadAllBytes($Path)
    # Protect-KitBytes зануляет $Plain в finally — открытый текст не остаётся в памяти.
    return (Protect-KitBytes -Plain $plain -Password $Password -Target $(if ($Target) { $Target } else { $Path + '.enc' }) -SourcePath $Path -KeepSource:$KeepSource)
}

function Protect-KitBytes([byte[]]$Plain, [string]$Password, [string]$Target, [string]$SourcePath = '', [switch]$KeepSource) {
    # Примечание: $Plain зануляется в finally. Вызывающий не должен
    # переиспользовать переданный массив после вызова.
    if ("$Password".Length -lt $script:KitMinPassword) { throw "Пароль короче $($script:KitMinPassword) символов." }
    if ($null -eq $Plain) { throw 'Нет данных для шифрования.' }
    if ($Plain.Length -gt $script:KitMaxFileSize) { throw 'Данные слишком велики (лимит 16 МиБ).' }
    $salt = New-KitRandom 16
    $iv = New-KitRandom 16
    $k = $null
    $aes = $null
    $ic = $null
    try {
        $k = Get-KitKeys $Password $salt $script:KitSecretIters 'SHA256'
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 256
        $aes.Key = $k.Enc
        $aes.IV = $iv
        $ic = $aes.CreateEncryptor()
        $enc = $ic.TransformFinalBlock($Plain, 0, $Plain.Length)

        $meta = @{
            _head = $script:KitEncHead
            iters = "$($script:KitSecretIters)"
            prf   = 'SHA256'
            salt  = [Convert]::ToBase64String($salt)
            iv    = [Convert]::ToBase64String($iv)
        }
        $aad = Get-KitAad $meta $iv
        $both = New-Object byte[] ($aad.Length + $iv.Length + $enc.Length)
        [Array]::Copy($aad, 0, $both, 0, $aad.Length)
        [Array]::Copy($iv, 0, $both, $aad.Length, $iv.Length)
        [Array]::Copy($enc, 0, $both, $aad.Length + $iv.Length, $enc.Length)
        $mac = Get-KitHmac $k.Mac $both
        Clear-KitBytes $both

        $txt = @(
            $script:KitEncHead
            "iters=$($script:KitSecretIters)"
            'prf=SHA256'
            'salt=' + $meta['salt']
            'iv=' + $meta['iv']
            'mac=' + [Convert]::ToBase64String($mac)
            'data=' + [Convert]::ToBase64String($enc)
        ) -join "`n"
        Clear-KitBytes $enc
        [IO.File]::WriteAllText($Target, $txt + "`n", (New-Object System.Text.UTF8Encoding $false))
        if (-not $KeepSource -and $SourcePath) {
            Remove-Item -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue
        }
        return $Target
    } finally {
        if ($ic) { $ic.Dispose() }
        if ($aes) { $aes.Dispose() }
        Clear-KitKeys $k
        Clear-KitBytes $Plain
    }
}

function Unprotect-KitFile([string]$EncPath, [string]$OutPath, [string]$Password) {
    # Расшифровывает .enc в файл OutPath. $null, если контейнер битый или пароль не тот.
    # Для флешки предпочтительнее Unprotect-KitBytes: он не пишет на носитель.
    $bytes = Unprotect-KitBytes -EncPath $EncPath -Password $Password
    if ($null -eq $bytes) { return $null }
    try {
        $dir = Split-Path -Parent $OutPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [IO.File]::WriteAllBytes($OutPath, $bytes)
        return $OutPath
    } finally { Clear-KitBytes $bytes }
}

function Unprotect-KitBytes([string]$EncPath, [string]$Password) {
    # Возвращает byte[] открытого текста. Вызывающий обязан занулить его сам
    # через Clear-KitBytes — здесь вернуть «уже занулённое» нельзя.
    if ("$Password".Length -lt 1) { return $null }
    $meta = Read-KitHeaders $EncPath
    if (-not $meta) { return $null }
    $legacy = ($meta['_head'] -eq $script:KitEncHead1)
    if (-not $legacy -and $meta['_head'] -ne $script:KitEncHead) { return $null }

    $salt = ConvertFrom-KitB64 $meta['salt']
    $iv   = ConvertFrom-KitB64 $meta['iv']
    $mac  = ConvertFrom-KitB64 $meta['mac']
    $data = ConvertFrom-KitB64 $meta['data']
    if (-not $salt -or -not $iv -or -not $mac -or -not $data) { return $null }
    if ($salt.Length -ne 16 -or $iv.Length -ne 16) { return $null }
    if ($mac.Length -ne 32) { return $null }
    if ($data.Length -lt 16 -or ($data.Length % 16) -ne 0) { return $null }

    $p = Get-KitParams $meta $script:KitEncHead $script:KitEncHead1
    if (-not $p) { return $null }

    $k = $null; $aes = $null; $ic = $null; $both = $null
    try {
        $k = Get-KitKeysRaw $Password $salt $p.Iters $(if ($p.Legacy) { 64 } else { 96 }) $p.Prf

        if ($p.Legacy) {
            # v1: MAC по iv+шифртекст, заголовок не покрыт.
            $both = New-Object byte[] ($iv.Length + $data.Length)
            [Array]::Copy($iv, 0, $both, 0, $iv.Length)
            [Array]::Copy($data, 0, $both, $iv.Length, $data.Length)
        } else {
            # v2: MAC по заголовку (AAD) + iv + шифртекст.
            $aad = Get-KitAad $meta $iv
            $both = New-Object byte[] ($aad.Length + $iv.Length + $data.Length)
            [Array]::Copy($aad, 0, $both, 0, $aad.Length)
            [Array]::Copy($iv, 0, $both, $aad.Length, $iv.Length)
            [Array]::Copy($data, 0, $both, $aad.Length + $iv.Length, $data.Length)
        }

        # MAC проверяется ДО расшифровки: иначе появляется padding oracle.
        if (-not (Test-KitMac (Get-KitHmac $k.Mac $both) $mac)) { return $null }

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 256
        $aes.Key = $k.Enc
        $aes.IV = $iv
        $ic = $aes.CreateDecryptor()
        try {
            return ,$ic.TransformFinalBlock($data, 0, $data.Length)
        } catch {
            # Сюда попадаем, только если MAC уже сошёлся, — случайность или баг.
            return $null
        }
    } catch {
        return $null
    } finally {
        Clear-KitBytes $both
        if ($ic) { $ic.Dispose() }
        if ($aes) { $aes.Dispose() }
        Clear-KitKeys $k
    }
}

# ── Обслуживание ────────────────────────────────────────────────────────────

function Read-KitYesNo([string]$Title, [string[]]$Lines, [int]$TimeoutSec = 30) {
    # Вопрос да/нет одной клавишей. Enter = НЕТ: на общей машине случайное
    # нажатие не должно подтверждать действие.
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    foreach ($l in $Lines) { Write-Host $l -ForegroundColor DarkGray }
    Write-Host ('    Y — да,   N — нет (Enter не нужен),   ' + $TimeoutSec + ' секунд без ответа — нет.') -ForegroundColor DarkGray
    Write-Host '    > ' -ForegroundColor Green -NoNewline
    try {
        # Нажатия до вопроса (лишние «q») ответом не считаем.
        Start-Sleep -Milliseconds 500
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    } catch { return $false }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Enter') { Write-Host ''; return $false }
                if ($k.Key -eq 'Escape') { Write-Host ''; return $false }
                $ch = "$($k.KeyChar)"
                if ($ch -match '^[yYnN]$') {
                    Write-Host $ch
                    return ($ch -match '^[yY]$')
                }
            }
        } catch { Write-Host ''; return $false }
        Start-Sleep -Milliseconds 100
    }
    Write-Host ''
    return $false
}

function Remove-KitPlain([string]$Vpn) {
    # Убирает открытые копии секретов, если рядом лежат их .enc.
    # ВНИМАНИЕ: на FAT32/exFAT это не стирание, а освобождение кластеров.
    # Функция нужна, чтобы не оставлять файлы видимыми в проводнике; против
    # восстановления она не защищает. Не создавайте открытый текст на флешке.
    $pairs = @(
        @{ plain = (Join-Path $Vpn 'config.json');          enc = (Join-Path $Vpn 'config.json.enc') },
        @{ plain = (Join-Path $Vpn 'config.json.bak.json'); enc = (Join-Path $Vpn 'config.json.bak.json.enc') },
        @{ plain = (Join-Path $Vpn 'sub.txt');              enc = (Join-Path $Vpn 'sub.txt.enc') }
    )
    $n = 0
    foreach ($p in $pairs) {
        if ((Test-Path -LiteralPath $p.enc) -and (Test-Path -LiteralPath $p.plain)) {
            Remove-Item -LiteralPath $p.plain -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $p.plain)) { $n++ }
        }
    }
    return $n
}

function Update-KitContainer([string]$EncPath, [string]$Password) {
    # Читает v1-контейнер и перезаписывает его как v2 (с AAD и разделёнными ключами).
    # Возвращает $true, если файл действительно обновлён.
    $meta = Read-KitHeaders $EncPath
    if (-not $meta) { return $false }
    if ($meta['_head'] -ne $script:KitEncHead1) { return $false }
    $bytes = Unprotect-KitBytes -EncPath $EncPath -Password $Password
    if ($null -eq $bytes) { return $false }
    try {
        $tmp = $EncPath + '.new'
        Protect-KitBytes -Plain $bytes -Password $Password -Target $tmp | Out-Null
        Move-Item -LiteralPath $tmp -Destination $EncPath -Force
        return $true
    } finally { Clear-KitBytes $bytes }
}

function Update-KitSecret([string]$Vpn, [string]$Password) {
    # Переводит kit-secret/1 в kit-secret/2 (96 байт, отдельный проверочный ключ).
    $meta = Read-KitHeaders (Get-KitSecretFile $Vpn)
    if (-not $meta) { return $false }
    if ($meta['_head'] -ne $script:KitSecretHead1) { return $false }
    if (-not (Test-KitPassword $Vpn $Password)) { return $false }
    Set-KitPasswordValue $Vpn $Password
    return $true
}

function Show-KitThreatModel {
    # Печатается один раз при -Setup: на общей машине человек должен понимать,
    # от чего защита есть, а от чего нет.
    Write-Host ''
    Write-Host 'Что защищает пароль на этой флешке:' -ForegroundColor Cyan
    Write-Host '  • потерю или кражу флешки;' -ForegroundColor DarkGray
    Write-Host '  • чтение ключей другим пользователем машины после выхода.' -ForegroundColor DarkGray
    Write-Host 'Чего он НЕ делает:' -ForegroundColor Cyan
    Write-Host '  • не защищает от вредоносной программы или администратора' -ForegroundColor DarkGray
    Write-Host '    на машине, пока скрипт работает (они видят память и нажатия);' -ForegroundColor DarkGray
    Write-Host '  • не стирает старые незашифрованные копии с носителя —' -ForegroundColor DarkGray
    Write-Host '    флешку лучше отформатировать на доверенной машине;' -ForegroundColor DarkGray
    Write-Host '  • не скрывает имена файлов и их размеры.' -ForegroundColor DarkGray
    Write-Host 'На общем ПК: закрой лишние окна, не оставляй сессию открытой,' -ForegroundColor Yellow
    Write-Host 'после работы выйди из VPN и вытащи флешку.' -ForegroundColor Yellow
    Write-Host ''
}
