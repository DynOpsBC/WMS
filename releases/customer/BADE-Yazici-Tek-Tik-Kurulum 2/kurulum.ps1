[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Windows.Forms

function Show-Error([string]$Message) {
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        'BADE BCWMS Yazici Kurulumu',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Show-Success([string]$PrinterName) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Kurulum tamamlandi.`r`n`r`nBelge yazicisi: $PrinterName`r`n`r`nEl terminalinde Yazicilar > Yenile > Belge secin.",
        'BADE BCWMS Yazici Kurulumu',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
}

try {
    $packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $agentZip = Join-Path $packageRoot 'bcwms-print-agent-1.0.0-win-x64.zip'
    $secretPath = Join-Path $packageRoot 'print-agent.runtime.secrets.json'

    if (-not (Test-Path -LiteralPath $agentZip -PathType Leaf)) {
        throw 'Ajan paketi eksik: bcwms-print-agent-1.0.0-win-x64.zip'
    }
    if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
        throw 'Musteriye ozel print-agent.runtime.secrets.json dosyasi paket icinde bulunamadi.'
    }

    $running = Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue
    if ($running) {
        throw "BCWMS Print Agent zaten calisiyor. Saat yanindaki simgeden Cikis deyip KURULUM.bat dosyasini tekrar acin."
    }

    $defaultPrinter = Get-CimInstance -ClassName Win32_Printer |
        Where-Object { $_.Default -eq $true } |
        Select-Object -First 1
    if ($null -eq $defaultPrinter -or [string]::IsNullOrWhiteSpace([string]$defaultPrinter.Name)) {
        throw 'Windows varsayilan yazicisi bulunamadi. Wi-Fi yaziciyi Windows Ayarlar > Yazicilar ve tarayicilar ekraninda varsayilan yapin.'
    }

    $printerName = ([string]$defaultPrinter.Name).Trim()
    if ($printerName -match '(?i)Microsoft Print to PDF|Microsoft XPS|OneNote|Fax') {
        throw "Windows varsayilan yazicisi fiziksel yazici degil: $printerName. Wi-Fi yaziciyi varsayilan yapip tekrar deneyin."
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
    $segments = $stationId.Split('.')
    $invalidSegments = @($segments | Where-Object { $_ -notmatch '^[A-Z0-9_-]{1,32}$' })
    if ($segments.Count -ne 4 -or $invalidSegments.Count -gt 0) {
        throw 'Secret dosyasindaki Station ID gecersiz.'
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

    $printerId = 'P' + [Guid]::NewGuid().ToString('N').Substring(0, 16).ToUpperInvariant()
    $printerMappings = [ordered]@{}
    $printerMappings[$printerName] = $printerId
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
        documentPrinterId = $printerId
        documentPrinterName = $printerName
        labelTransport = 0
        labelFormat = 'ZPL'
        maxDeliveryAttempts = 5
        maxPayloadBytes = 52428800
        heartbeatSeconds = 300
        printerIdsByName = $printerMappings
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
    [IO.File]::WriteAllBytes($configPath, $data)
    [Array]::Clear($data, 0, $data.Length)

    # Secret artik Windows kullanicisina bagli DPAPI dosyasinda korunuyor.
    Remove-Item -LiteralPath $secretPath -Force

    $installedExe = Join-Path $env:LOCALAPPDATA 'Programs\BCWMS Print Agent\BCWMS.PrintAgent.exe'
    if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
        throw 'Kurulum tamamlandi ancak BCWMS.PrintAgent.exe bulunamadi.'
    }
    Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Parent $installedExe)
    Start-Sleep -Seconds 3
    Show-Success $printerName
}
catch {
    Show-Error $_.Exception.Message
    Write-Error $_
    exit 1
}
