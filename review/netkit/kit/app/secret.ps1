# secret.ps1 — парольная защита ключей на флешке: PBKDF2 + AES-256-CBC + HMAC-SHA256.
#
# Зачем: vpn\config.json (UUID узлов) и vpn\sub.txt (URL подписки с токеном)
# лежат открытым текстом. С паролем на флешке остаются только *.enc.
#
# Как устроено:
#   vpn\secret.dat  — соль, число итераций и проверочный HMAC. Сам пароль НЕ хранится.
#   vpn\*.enc       — kit-enc/1, salt, iv, mac, data (base64).
# Ключ = PBKDF2(пароль, соль, 200000) = 64 байта: 32 на AES, 32 на HMAC.
# MAC считается по iv+шифртекст (encrypt-then-MAC) и сравнивается за постоянное время.
#
# Забыли пароль — расшифровать нельзя, ключи считаются потерянными:
# дома заново ввести ссылки (пункт 4) и перевыпустить подписку (пункт 3).

$script:KitSecretIters = 200000
$script:KitSecretHead = 'kit-secret/1'
$script:KitEncHead    = 'kit-enc/1'
$script:KitSecretCheck = 'kit-secret-check'

function Get-KitSecretFile([string]$Vpn) { Join-Path $Vpn 'secret.dat' }
function Test-KitSecret([string]$Vpn) { Test-Path (Get-KitSecretFile $Vpn) }

function New-KitRandom([int]$Len) {
    $b = New-Object byte[] $Len
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ,$b
}

function Invoke-KitPbkdf2([string]$Password, [byte[]]$Salt, [int]$Iters, [int]$Len = 64) {
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iters)
    try { return ,$kdf.GetBytes($Len) } finally { $kdf.Dispose() }
}

function Get-KitKeys([string]$Password, [byte[]]$Salt, [int]$Iters) {
    # 64 байта -> @{Enc=32 байта; Mac=32 байта}
    $all = Invoke-KitPbkdf2 $Password $Salt $Iters 64
    $enc = New-Object byte[] 32
    $mac = New-Object byte[] 32
    [Array]::Copy($all, 0, $enc, 0, 32)
    [Array]::Copy($all, 32, $mac, 0, 32)
    return @{ Enc = $enc; Mac = $mac }
}

function Get-KitHmac([byte[]]$Key, [byte[]]$Data) {
    $h = New-Object System.Security.Cryptography.HMACSHA256(, $Key)
    try { return ,$h.ComputeHash($Data) } finally { $h.Dispose() }
}

function Test-KitMac([byte[]]$A, [byte[]]$B) {
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $d = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $d = $d -bor ($A[$i] -bxor $B[$i]) }
    return ($d -eq 0)
}

function Read-KitHeaders([string]$Path) {
    # key=value построчно; первая строка — заголовок формата
    $h = @{ _head = '' }
    if (-not (Test-Path $Path)) { return $null }
    $lines = @()
    try { $lines = [IO.File]::ReadAllLines($Path) } catch { return $null }
    if ($lines.Count -lt 1) { return $null }
    $h['_head'] = "$($lines[0])".Trim()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^([A-Za-z0-9_]+)=(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() }
    }
    return $h
}

function ConvertFrom-KitB64([string]$S) {
    if (-not $S) { return $null }
    try { return ,[Convert]::FromBase64String($S) } catch { return $null }
}

function Set-KitPasswordValue([string]$Vpn, [string]$Password) {
    # неинтерактивно: записать secret.dat для пароля (нужно для тестов и для смены)
    if ("$Password".Length -lt 8) { throw 'Пароль короче 8 символов.' }
    New-Item -ItemType Directory -Force -Path $Vpn | Out-Null
    $salt = New-KitRandom 16
    $k = Get-KitKeys $Password $salt $script:KitSecretIters
    $check = Get-KitHmac $k.Mac ([Text.Encoding]::UTF8.GetBytes($script:KitSecretCheck))
    $txt = @(
        $script:KitSecretHead
        'iters=' + $script:KitSecretIters
        'salt=' + [Convert]::ToBase64String($salt)
        'check=' + [Convert]::ToBase64String($check)
    ) -join "`r`n"
    [IO.File]::WriteAllText((Get-KitSecretFile $Vpn), $txt + "`r`n", (New-Object System.Text.UTF8Encoding $false))
}

function ConvertFrom-Secure([System.Security.SecureString]$S) {
    if ($null -eq $S) { return '' }
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($S)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Set-KitPassword([string]$Vpn) {
    # интерактивно: придумать пароль и записать secret.dat
    if (Test-KitSecret $Vpn) { throw 'Пароль уже задан.' }
    while ($true) {
        $p1 = ConvertFrom-Secure (Read-Host 'Придумай пароль (минимум 8 символов)' -AsSecureString)
        if ($p1.Length -lt 8) { Write-Host '[!] Короче 8 символов — ещё раз.' -ForegroundColor Red; continue }
        $p2 = ConvertFrom-Secure (Read-Host 'Повтори пароль' -AsSecureString)
        if ($p1 -ne $p2) { Write-Host '[!] Не совпало — ещё раз.' -ForegroundColor Red; continue }
        Set-KitPasswordValue $Vpn $p1
        Write-Host '[+] Пароль задан. Вводить его нужно при каждом подключении.' -ForegroundColor Green
        Write-Host '[i] Запиши пароль в надёжном месте: восстановить его нельзя,' -ForegroundColor Yellow
        Write-Host '    без него не прочитать config.json и sub.txt.' -ForegroundColor Yellow
        return $p1
    }
}

function Test-KitPassword([string]$Vpn, [string]$Password) {
    $meta = Read-KitHeaders (Get-KitSecretFile $Vpn)
    if (-not $meta) { return $false }
    if ($meta['_head'] -ne $script:KitSecretHead) { return $false }
    $salt = ConvertFrom-KitB64 $meta['salt']
    $want = ConvertFrom-KitB64 $meta['check']
    $iters = 0
    if (-not [int]::TryParse("$($meta['iters'])", [ref]$iters) -or $iters -lt 1000) { return $false }
    $k = Get-KitKeys $Password $salt $iters
    $got = Get-KitHmac $k.Mac ([Text.Encoding]::UTF8.GetBytes($script:KitSecretCheck))
    return (Test-KitMac $got $want)
}

function Read-KitPassword([string]$Vpn, [int]$Tries = 3) {
    # спрашивает пароль до 3 раз; '' при отказе (вызывающий сам решает, как упасть)
    if (-not (Test-KitSecret $Vpn)) { return '' }
    try {
        if ([Console]::IsInputRedirected) {
            Write-Host '[X] Ключи зашифрованы паролем, а ввод перенаправлен — пароль ввести некуда.' -ForegroundColor Red
            return ''
        }
    } catch { }
    for ($i = 1; $i -le $Tries; $i++) {
        $p = ''
        try { $p = ConvertFrom-Secure (Read-Host 'Пароль флешки' -AsSecureString) } catch { return '' }
        if (-not $p) { Write-Host '[!] Пустой пароль.' -ForegroundColor Red; continue }
        if (Test-KitPassword $Vpn $p) { return $p }
        Write-Host "[!] Неверный пароль (попытка $i из $Tries)." -ForegroundColor Red
    }
    return ''
}

function Protect-KitFile([string]$Path, [string]$Password, [string]$Target = '', [switch]$KeepSource) {
    # шифрует файл в <Path>.enc (или Target); исходник удаляет, если не -KeepSource
    $out = $Target
    if (-not $out) { $out = $Path + '.enc' }
    $salt = New-KitRandom 16
    $iv = New-KitRandom 16
    $k = Get-KitKeys $Password $salt $script:KitSecretIters
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 256
        $aes.Key = $k.Enc
        $aes.IV = $iv
        $plain = [IO.File]::ReadAllBytes($Path)
        $enc = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
    } finally { $aes.Dispose() }

    $both = New-Object byte[] ($iv.Length + $enc.Length)
    [Array]::Copy($iv, 0, $both, 0, $iv.Length)
    [Array]::Copy($enc, 0, $both, $iv.Length, $enc.Length)
    $mac = Get-KitHmac $k.Mac $both

    $txt = @(
        $script:KitEncHead
        'iters=' + $script:KitSecretIters
        'salt=' + [Convert]::ToBase64String($salt)
        'iv=' + [Convert]::ToBase64String($iv)
        'mac=' + [Convert]::ToBase64String($mac)
        'data=' + [Convert]::ToBase64String($enc)
    ) -join "`r`n"
    [IO.File]::WriteAllText($out, $txt + "`r`n", (New-Object System.Text.UTF8Encoding $false))
    if (-not $KeepSource) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
    return $out
}

function Unprotect-KitFile([string]$EncPath, [string]$OutPath, [string]$Password) {
    # расшифровывает .enc в OutPath; $null, если файл битый или пароль не тот
    if (-not (Test-Path $EncPath)) { return $null }
    $meta = Read-KitHeaders $EncPath
    if (-not $meta) { return $null }
    if ($meta['_head'] -ne $script:KitEncHead) { return $null }
    $salt = ConvertFrom-KitB64 $meta['salt']
    $iv   = ConvertFrom-KitB64 $meta['iv']
    $mac  = ConvertFrom-KitB64 $meta['mac']
    $data = ConvertFrom-KitB64 $meta['data']
    if (-not $salt -or -not $iv -or -not $mac -or -not $data) { return $null }
    $iters = 0
    if (-not [int]::TryParse("$($meta['iters'])", [ref]$iters) -or $iters -lt 1000) { return $null }

    $k = Get-KitKeys $Password $salt $iters
    $both = New-Object byte[] ($iv.Length + $data.Length)
    [Array]::Copy($iv, 0, $both, 0, $iv.Length)
    [Array]::Copy($data, 0, $both, $iv.Length, $data.Length)
    if (-not (Test-KitMac (Get-KitHmac $k.Mac $both) $mac)) { return $null }

    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 256
        $aes.Key = $k.Enc
        $aes.IV = $iv
        $plain = $aes.CreateDecryptor().TransformFinalBlock($data, 0, $data.Length)
    } catch { return $null } finally { $aes.Dispose() }

    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllBytes($OutPath, $plain)
    return $OutPath
}

function Read-KitYesNo([string]$Title, [string[]]$Lines, [int]$TimeoutSec = 30) {
    # вопрос да/нет по одной клавише; при перенаправленном вводе — сразу "нет"
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    foreach ($l in $Lines) { Write-Host $l -ForegroundColor DarkGray }
    Write-Host ('    Enter или Y — да,   N — нет,   ' + $TimeoutSec + ' секунд без ответа — пропустить.') -ForegroundColor DarkGray
    Write-Host '    > ' -ForegroundColor Green -NoNewline
    $buf = ''
    $answered = $false
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Enter') { $answered = $true; break }
                if ($k.Key -eq 'Escape') { Write-Host ''; return $false }
                if ("$($k.KeyChar)" -match '^[A-Za-zА-Яа-я]$') { $buf += $k.KeyChar; Write-Host $k.KeyChar -NoNewline }
            }
        } catch { return $false }
        Start-Sleep -Milliseconds 100
    }
    Write-Host ''
    if (-not $answered) { return $false }
    if ($buf -eq '') { return $true }
    return ($buf -match '^(y|Y|д|Д)')
}

function Remove-KitPlain([string]$Vpn) {
    # убирает открытые копии секретов, если рядом лежат их .enc
    $pairs = @(
        @{ plain = (Join-Path $Vpn 'config.json');              enc = (Join-Path $Vpn 'config.json.enc') },
        @{ plain = (Join-Path $Vpn 'config.json.bak.json');     enc = (Join-Path $Vpn 'config.json.bak.json.enc') },
        @{ plain = (Join-Path $Vpn 'sub.txt');                  enc = (Join-Path $Vpn 'sub.txt.enc') }
    )
    $n = 0
    foreach ($p in $pairs) {
        if ((Test-Path $p.enc) -and (Test-Path $p.plain)) {
            Remove-Item $p.plain -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $p.plain)) { $n++ }
        }
    }
    return $n
}
