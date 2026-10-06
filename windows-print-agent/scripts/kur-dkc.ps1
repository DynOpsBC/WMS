$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$packageRoot = Join-Path $PSScriptRoot 'BCWMS-Print-Agent-win-x64'
$secretsSource = Join-Path $PSScriptRoot 'print-agent.runtime.secrets.json'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs/BCWMS Print Agent'
$agentExe = Join-Path $installDir 'BCWMS.PrintAgent.exe'
try {
    # Validate before stopping an existing installation. Never print credentials.
    $settings = Get-Content -LiteralPath $secretsSource -Raw | ConvertFrom-Json
    if ($settings.schemaVersion -ne 1 -or $settings.stationId -ne 'DKC.DKC.MAIN.WMS02') {
        throw 'Bu paket yalniz DKC.DKC.MAIN.WMS02 istasyonu icindir.'
    }
    if (([DateTimeOffset]$settings.blobSasExpiresAtUtc) -le [DateTimeOffset]::UtcNow) {
        throw 'DKC baglanti dosyasinin suresi dolmus.'
    }
    foreach ($field in @('printJobsListenConnectionString', 'printerStatusSendConnectionString', 'blobReadSasToken')) {
        if ([string]::IsNullOrWhiteSpace($settings.agent.$field)) { throw 'DKC baglanti dosyasi eksik.' }
    }
    $running = Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $agentExe -and $_.SessionId -eq (Get-Process -Id $PID).SessionId }
    if ($running) {
        Write-Host '  Calisan ajan kapatiliyor...'
        foreach ($process in $running) { $null = $process.CloseMainWindow() }
        Start-Sleep -Seconds 3
        foreach ($process in $running) {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        }
        Start-Sleep -Seconds 1
    }
    Write-Host '  Agent kuruluyor; paket butunlugu dogrulaniyor...'
    & (Join-Path $packageRoot 'installer/install.ps1') -DoNotStart
    if (-not $?) { throw 'Agent kurulumu basarisiz.' }
    if (-not (Test-Path -LiteralPath $agentExe -PathType Leaf)) { throw 'Agent uygulamasi bulunamadi.' }
    Copy-Item -LiteralPath $secretsSource -Destination (Join-Path $installDir 'print-agent.runtime.secrets.json') -Force
    Write-Host '  DKC baglanti dosyasi yerlestirildi; Agent aciliyor...'
    Start-Process -FilePath $agentExe -WorkingDirectory $installDir | Out-Null
    Write-Host ''
    Write-Host '  TAMAM. Ilk kurulumda Azure alanlari otomatik doldurulur.'
    Write-Host '  Yazicilari isaretleyin, gorunen adlarini yazin.'
    Write-Host '  Ayarlari Kaydet ve Baglan -> Buluta Esitle.'
    Write-Host '  Mevcut kurulumda yazici secimleri korunur.'
    Write-Host '  Mevcut istasyon farkliysa Agent onu degistirmez; bu paket WMS02 icindir.'
}
catch {
    Write-Host '  KURULUM BASARISIZ.' -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
