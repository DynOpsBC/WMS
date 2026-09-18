$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$packageRoot = Join-Path $PSScriptRoot 'BCWMS-Print-Agent-win-x64'
$agentExe = Join-Path $env:LOCALAPPDATA 'Programs/BCWMS Print Agent/BCWMS.PrintAgent.exe'
try {
    # Check payload before stopping the current agent. Installer rechecks all files.
    $manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'manifest.sha256.json') -Raw | ConvertFrom-Json
    if ($manifest.productId -ne 'DynOps.BCWMS.PrintAgent' -or $manifest.productVersion -ne '1.1.3') {
        throw 'Beklenen Print Agent 1.1.3 paketi bulunamadi.'
    }
    foreach ($entry in $manifest.files) {
        $relative = [string]$entry.path
        if ($relative.Contains('..') -or $relative.Contains(':') -or $relative.StartsWith('/') -or $relative.Contains('\')) {
            throw 'Paket dosya yolu gecersiz.'
        }
        $file = Join-Path $packageRoot $relative
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Paket dogrulanamadi: $relative"
        }
    }
    $sessionId = (Get-Process -Id $PID).SessionId
    $running = @(Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $agentExe -and $_.SessionId -eq $sessionId })
    foreach ($process in $running) { $null = $process.CloseMainWindow() }
    if ($running.Count -gt 0) {
        Start-Sleep -Seconds 3
        foreach ($process in $running) {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        }
    }
    Write-Host 'Print Agent 1.1.3 kuruluyor...'
    & (Join-Path $packageRoot 'installer/install.ps1') -DoNotStart
    if (-not $?) { throw 'Kurulum tamamlanamadi.' }
    if (-not (Test-Path -LiteralPath $agentExe -PathType Leaf)) { throw 'Agent uygulamasi bulunamadi.' }
    Start-Process -FilePath $agentExe -WorkingDirectory (Split-Path -Parent $agentExe) | Out-Null
    Write-Host 'TAMAM. Agent acildi. Mevcut baglanti ve yazici ayarlari korunur.'
    Write-Host 'Gorunen adlari yazin: Ayarlari Kaydet ve Baglan -> Buluta Esitle.'
} catch {
    Write-Host 'KURULUM BASARISIZ:' -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
