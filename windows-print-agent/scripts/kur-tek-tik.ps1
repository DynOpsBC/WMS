<#
  Tek tıkla kurulum (KUR.cmd bunu çağırır):
  çalışan ajanı kapatır, install.ps1 ile paketi kurar, otomatik başlatmayı
  açar ve ajanı yeniden başlatır. install.ps1'in bütünlük/hash kontrolleri
  aynen çalışır; bu betik yalnız operatörün elle yaptığı adımları üstlenir.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$installerDir = $PSScriptRoot
$packageRoot = Split-Path -Parent $installerDir
$agentExe = Join-Path $env:LOCALAPPDATA 'Programs\BCWMS Print Agent\BCWMS.PrintAgent.exe'

try {
    $running = Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host '  Çalışan ajan kapatılıyor...'
        foreach ($process in $running) {
            $null = $process.CloseMainWindow()
        }
        Start-Sleep -Seconds 3
        $still = Get-Process -Name 'BCWMS.PrintAgent' -ErrorAction SilentlyContinue
        if ($still) {
            $still | Stop-Process -Force
            Start-Sleep -Seconds 2
        }
        Write-Host '  Ajan kapatıldı.'
    }

    Write-Host '  Dosyalar kuruluyor (bütünlük doğrulanıyor)...'
    & (Join-Path $installerDir 'install.ps1') -DoNotStart
    # install.ps1 bir betik: $LASTEXITCODE yalniz yerel exe'lerden sonra set
    # edilir; StrictMode altinda okumak hata verir (BADE, 17 Eyl). $? yeterli.
    if (-not $?) {
        throw 'Kurulum betigi hata verdi.'
    }

    Write-Host '  Otomatik başlatma ayarlanıyor...'
    & (Join-Path $installerDir 'enable-autostart.ps1')

    if (-not (Test-Path -LiteralPath $agentExe -PathType Leaf)) {
        throw "Ajan çalıştırılabiliri bulunamadı: $agentExe"
    }
    Write-Host '  Ajan başlatılıyor...'
    Start-Process -FilePath $agentExe | Out-Null

    Write-Host ''
    Write-Host '  ================================================================'
    Write-Host '  KURULUM TAMAM. Ajan penceresi açıldı.'
    Write-Host ''
    Write-Host '  Sırada:'
    Write-Host '    1) Yazicilar sekmesi -> "Etiket yazicilari" listesinde'
    Write-Host '       kullanacaginiz HER Zebra yaziciyi isaretleyin.'
    Write-Host '    2) "Etiket formati" = ZPL olmali (RAW ise etiket basilmaz).'
    Write-Host '    3) "Ayarlari Kaydet ve Baglan" -> sonra "Buluta Esitle".'
    Write-Host '    4) "Etiket Testi" ile her yazicidan cikti alin.'
    Write-Host '  ================================================================'
}
catch {
    Write-Host ''
    Write-Host '  *** KURULUM BASARISIZ ***' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Bu pencerenin ekran goruntusunu gonderin.'
    exit 1
}
