[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Windows.Forms

function Show-Error([string]$Message) {
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        'KITOKO BCWMS Yazici Kurulumu',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Show-Success() {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Kurulum tamamlandi.`r`n`r`nKITOKO baglanti ayarlari hazir ve Windows kullanicisina sifreli kaydedildi.`r`n`r`nAcilan panelde Yazicilar sekmesine gecin. Etiket ve/veya belge yazicisini secip Ayarlari Kaydet ve Baglan dugmesine basin.`r`n`r`nWindows acildiginda ajan otomatik baslar.",
        'KITOKO BCWMS Yazici Kurulumu',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Read-AgentSettings {
    $path = Join-Path $env:LOCALAPPDATA 'DynOps\BCWMS Print Agent\agent.config.dpapi'
    $data = [IO.File]::ReadAllBytes($path)
    $magic = [Text.Encoding]::UTF8.GetBytes("BCWMSCFG1`0")
    if ($data.Length -le $magic.Length) { throw 'Mevcut ajan ayari gecersiz; degistirilmedi.' }
    for ($i = 0; $i -lt $magic.Length; $i++) {
        if ($data[$i] -ne $magic[$i]) { throw 'Mevcut ajan ayari taninmiyor; degistirilmedi.' }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $entropy = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('DynOps.BCWMS.PrintAgent.Settings.v1')) }
    finally { $sha.Dispose() }
    $clear = $null
    try {
        $cipher = New-Object byte[] ($data.Length - $magic.Length)
        [Array]::Copy($data, $magic.Length, $cipher, 0, $cipher.Length)
        $clear = [Security.Cryptography.ProtectedData]::Unprotect($cipher, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ([Text.Encoding]::UTF8.GetString($clear) | ConvertFrom-Json)
    } finally {
        if ($null -ne $clear) { [Array]::Clear($clear, 0, $clear.Length) }
        [Array]::Clear($entropy, 0, $entropy.Length)
    }
}

try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows 10/11 64-bit gereklidir.' }
    $packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $agentZip = Join-Path $packageRoot 'bcwms-print-agent-1.0.0-win-x64.zip'
    $secretPath = Join-Path $packageRoot 'print-agent.runtime.secrets.json'

    if (-not (Test-Path -LiteralPath $agentZip -PathType Leaf)) {
        throw 'Ajan paketi eksik: bcwms-print-agent-1.0.0-win-x64.zip'
    }
    $running = Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue
    if ($running) {
        throw "BCWMS Print Agent zaten calisiyor. Saat yanindaki simgeden Cikis deyip KURULUM.bat dosyasini tekrar acin."
    }

    if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
        if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'DynOps\BCWMS Print Agent\agent.config.dpapi')) {
            $existing = Read-AgentSettings
            if ($existing.stationId -cne 'KITOKO.KITOKO.MAIN.PRINT01') { throw 'Bu Windows kullanicisinda baska bir istasyon kurulu. Ayarlara dokunulmadi.' }
            $exe = Join-Path $env:LOCALAPPDATA 'Programs\BCWMS Print Agent\BCWMS.PrintAgent.exe'
            if (-not (Test-Path -LiteralPath $exe)) { throw 'Ajan eksik; orijinal ZIP dosyasini yeniden cikartin.' }
            Start-Process -FilePath $exe
            Show-Success
            exit 0
        }
        throw 'Ozel ayar dosyasi eksik; orijinal KITOKO ZIP dosyasini yeniden cikartin.'
    }

    $existingSettings = $null
    $configPath = Join-Path $env:LOCALAPPDATA 'DynOps\BCWMS Print Agent\agent.config.dpapi'
    if (Test-Path -LiteralPath $configPath) {
        $existingSettings = Read-AgentSettings
        if ($existingSettings.stationId -cne 'KITOKO.KITOKO.MAIN.PRINT01') {
            throw 'Bu Windows kullanicisinda baska bir musteri/istasyon kurulu. Mevcut ayarlara dokunulmadi.'
        }
    }

    $secretFile = Get-Item -LiteralPath $secretPath
    if ($secretFile.Length -le 0 -or $secretFile.Length -gt 1MB) {
        throw 'print-agent.runtime.secrets.json dosyasi gecersiz boyutta.'
    }
    $secret = Get-Content -LiteralPath $secretPath -Raw | ConvertFrom-Json
    if ([int]$secret.schemaVersion -ne 1) {
        throw 'print-agent.runtime.secrets.json schemaVersion 1 olmalidir.'
    }

    $stationId = ([string]$secret.stationId).Trim()
    if ($stationId -cne 'KITOKO.KITOKO.MAIN.PRINT01') { throw 'Paket KITOKO istasyonuna ait degil.' }
    $segments = @($stationId -split '[.]')
    if ($segments.Length -ne 4) {
        throw "Secret dosyasindaki Station ID dort bolumlu degil: '$stationId'"
    }
    if ([string]$secret.routing.tenantId -cne $segments[0] -or
        [string]$secret.routing.companyId -cne $segments[1]) {
        throw 'Secret routing bilgisi Station ID ile uyusmuyor.'
    }
    if ([string]$secret.agent.blobContainerName -cne 'print-jobs') {
        throw 'Secret dosyasindaki Blob container gecersiz.'
    }

    $expiry = [DateTimeOffset]::Parse(
        [string]$secret.blobSasExpiresAtUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
    if ($expiry -le [DateTimeOffset]::UtcNow) {
        throw 'Print Agent secret suresi dolmus. Yeni secret paketi gereklidir.'
    }

    $expectedHash = '__AGENT_SHA256__'
    if ((Get-FileHash -LiteralPath $agentZip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash) { throw 'Ajan paketi butunluk kontrolu basarisiz. ZIP dosyasini yeniden cikartin.' }

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('bcwms-install-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        Expand-Archive -LiteralPath $agentZip -DestinationPath $temporaryRoot
        $agentPackage = Join-Path $temporaryRoot 'BCWMS-Print-Agent-win-x64'
        $installer = Join-Path $agentPackage 'installer\install.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw 'Dogrulanmis ajan installer dosyasi pakette bulunamadi.'
        }

        & $installer -DoNotStart
        if (-not $?) {
            throw 'BCWMS Print Agent kurulumu basarisiz.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $printerMappings = [ordered]@{}
    $blobAccount = ([string]$secret.agent.blobAccountName).Trim()

    $settings = [ordered]@{
        schemaVersion = 1
        agentId = [Guid]::NewGuid().ToString('D')
        tenantId = [string]$secret.routing.tenantId
        companyId = [string]$secret.routing.companyId
        stationId = $stationId
        jobsListenConnectionString = ([string]$secret.agent.printJobsListenConnectionString).Trim()
        statusSendConnectionString = ([string]$secret.agent.printerStatusSendConnectionString).Trim()
        storageAccount = $blobAccount
        blobEndpoint = "https://$blobAccount.blob.core.windows.net"
        blobReadSas = ([string]$secret.agent.blobReadSasToken).Trim().TrimStart('?')
        blobSasExpiresAtUtc = $expiry.ToString('O')
        labelPrinterId = ''
        labelPrinterName = ''
        documentPrinterId = ''
        documentPrinterName = ''
        labelTransport = 0
        labelFormat = 'ZPL'
        maxDeliveryAttempts = 5
        maxPayloadBytes = 52428800
        heartbeatSeconds = 300
        printerIdsByName = $printerMappings
    }

    if ($null -ne $existingSettings) {
        foreach ($name in @('agentId','labelPrinterId','labelPrinterName','documentPrinterId','documentPrinterName','labelTransport','labelFormat','printerIdsByName')) {
            if ($null -ne $existingSettings.PSObject.Properties[$name]) { $settings[$name] = $existingSettings.$name }
        }
    }

    $json = $settings | ConvertTo-Json -Depth 8 -Compress
    $clear = [Text.Encoding]::UTF8.GetBytes($json)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $entropy = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes('DynOps.BCWMS.PrintAgent.Settings.v1'))
    }
    finally {
        $sha256.Dispose()
    }

    try {
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $clear,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }
    finally {
        [Array]::Clear($clear, 0, $clear.Length)
        [Array]::Clear($entropy, 0, $entropy.Length)
    }

    $magic = [Text.Encoding]::UTF8.GetBytes("BCWMSCFG1`0")
    $data = New-Object byte[] ($magic.Length + $encrypted.Length)
    [Array]::Copy($magic, 0, $data, 0, $magic.Length)
    [Array]::Copy($encrypted, 0, $data, $magic.Length, $encrypted.Length)
    [Array]::Clear($encrypted, 0, $encrypted.Length)

    $dataDirectory = Join-Path $env:LOCALAPPDATA 'DynOps\BCWMS Print Agent'
    New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    $configPath = Join-Path $dataDirectory 'agent.config.dpapi'
    $pending = $configPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($pending, $data)
        if (Test-Path -LiteralPath $configPath) { [IO.File]::Replace($pending, $configPath, $null) }
        else { [IO.File]::Move($pending, $configPath) }
    } finally {
        if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
    }
    [Array]::Clear($data, 0, $data.Length)

    # Secret artik Windows kullanicisina bagli DPAPI dosyasinda korunuyor.
    Remove-Item -LiteralPath $secretPath -Force

    $installedExe = Join-Path $env:LOCALAPPDATA 'Programs\BCWMS Print Agent\BCWMS.PrintAgent.exe'
    if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
        throw 'Kurulum tamamlandi ancak BCWMS.PrintAgent.exe bulunamadi.'
    }
    & (Join-Path (Split-Path -Parent $installedExe) 'installer\enable-autostart.ps1') -ExecutablePath $installedExe
    if (-not $?) { throw 'Otomatik baslatma ayarlanamadi.' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'KITOKO Yazici Ajani.lnk'))
    $shortcut.TargetPath = $installedExe
    $shortcut.WorkingDirectory = Split-Path -Parent $installedExe
    $shortcut.Save()
    Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Parent $installedExe)
    Start-Sleep -Seconds 3
    Show-Success
}
catch {
    Show-Error $_.Exception.Message
    Write-Error $_
    exit 1
}
