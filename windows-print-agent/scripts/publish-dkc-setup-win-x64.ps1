[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [switch]$SkipTests,
    [string]$SigningScript = '',
    [switch]$AllowUnsignedSandboxBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Paketleme için PowerShell 7 veya üzeri gereklidir.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agentProject = Join-Path $projectRoot 'src/BCWMS.PrintAgent.Windows/BCWMS.PrintAgent.Windows.csproj'
$setupProject = Join-Path $projectRoot 'src/DKCProduction.PrintAgent.Setup/DKCProduction.PrintAgent.Setup.csproj'
$distRoot = Join-Path $projectRoot 'dist'
$packageRoot = Join-Path $distRoot 'DKC-Production-Print-Agent-win-x64'
$payloadZip = Join-Path $distRoot 'DKC-Production-Print-Agent-payload.zip'
$setupBuildRoot = Join-Path $distRoot '.dkc-setup-build'
$setupOutput = Join-Path $distRoot 'DKC-Production-Print-Agent-Setup.exe'
$hashOutput = Join-Path $distRoot 'DKC-Production-Print-Agent-Setup.sha256.txt'
$productId = 'DynOps.DKCProduction.PrintAgent'
$productVersion = '1.0.0'

$dotnetVersion = (& dotnet --version).Trim()
if ([version]$dotnetVersion -lt [version]'10.0.100') {
    throw ".NET SDK 10.0.100 veya üzeri gerekli. Bulunan: $dotnetVersion"
}

if ([string]::IsNullOrWhiteSpace($SigningScript) -and -not $AllowUnsignedSandboxBuild) {
    throw 'Müşteriye verilecek Setup.exe Authenticode imzalı olmalıdır. Yalnız iç Sandbox testi için -AllowUnsignedSandboxBuild kullanın.'
}

if (-not $SkipTests) {
    & dotnet test (Join-Path $projectRoot 'BCWMS.PrintAgent.sln') -c $Configuration -p:EnableWindowsTargeting=true
    if ($LASTEXITCODE -ne 0) { throw 'Testler başarısız; DKC paketi üretilmedi.' }
}

foreach ($path in @($packageRoot, $setupBuildRoot)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}
foreach ($path in @($payloadZip, $setupOutput, $hashOutput)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $setupBuildRoot -Force | Out-Null

& dotnet publish $agentProject `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:EnableWindowsTargeting=true `
    -p:ProductFlavor=DKCProduction `
    -p:PublishSingleFile=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $packageRoot
if ($LASTEXITCODE -ne 0) { throw 'DKC win-x64 agent publish başarısız.' }

$requiredFiles = @(
    (Join-Path $packageRoot 'DKCProduction.PrintAgent.exe'),
    (Join-Path $packageRoot 'DKCProduction.PrintAgent.dll'),
    (Join-Path $packageRoot 'BCWMS.PrintAgent.Core.dll'),
    (Join-Path $packageRoot 'Azure.Messaging.ServiceBus.dll'),
    (Join-Path $packageRoot 'Azure.Storage.Blobs.dll'),
    (Join-Path $packageRoot 'PdfiumViewer.dll'),
    (Join-Path $packageRoot 'pdfium.dll')
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Publish çıktısında zorunlu dosya yok: $requiredFile"
    }
}
if (Test-Path -LiteralPath (Join-Path $packageRoot 'BCWMS.PrintAgent.exe')) {
    throw 'DKC payload yanlışlıkla WMS ana executable dosyasını içeriyor.'
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'DKC-README.md') -Destination (Join-Path $packageRoot 'README.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD-PARTY-NOTICES.md') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses') -Destination (Join-Path $packageRoot 'licenses') -Recurse

$authenticodeSigned = $false
$signingScriptPath = ''
if (-not [string]::IsNullOrWhiteSpace($SigningScript)) {
    if (-not $IsWindows) { throw 'Authenticode imzalama yalnız Windows yayın makinesinde desteklenir.' }
    $signingScriptPath = (Resolve-Path -LiteralPath $SigningScript).Path
    & $signingScriptPath -FilePath (Join-Path $packageRoot 'DKCProduction.PrintAgent.exe')
    if ($LASTEXITCODE -ne 0) { throw 'DKC agent Authenticode imzalama başarısız.' }
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $packageRoot 'DKCProduction.PrintAgent.exe')
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "DKC agent imzası doğrulanamadı: $($signature.Status)"
    }
    $authenticodeSigned = $true
}

$secretFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Where-Object {
    $_.Name.EndsWith('.secrets.json', [StringComparison]::OrdinalIgnoreCase)
})
if ($secretFiles.Count -gt 0) {
    throw 'Paket plaintext *.secrets.json içeriyor; secret sızıntısını önlemek için paket üretilmedi.'
}

$textExtensions = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
@('.config', '.json', '.md', '.txt', '.xml') | ForEach-Object { [void]$textExtensions.Add($_) }
foreach ($textFile in Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Where-Object { $textExtensions.Contains($_.Extension) }) {
    $content = Get-Content -LiteralPath $textFile.FullName -Raw
    if ($content -match 'SharedAccessKey=[A-Za-z0-9+/]{40,}={0,2}(?:;|$)' -or
        $content -match '(?:\?|&)sig=[A-Za-z0-9%_-]{20,}') {
        throw "Paket olası canlı connection string/SAS secret içeriyor: $($textFile.Name)"
    }
}

$hashes = Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\', '/')
    [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
[ordered]@{
    schemaVersion = 1
    productId = $productId
    productVersion = $productVersion
    runtime = 'win-x64'
    selfContained = $true
    authenticodeSigned = $authenticodeSigned
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    files = @($hashes)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.sha256.json') -Encoding utf8NoBOM

Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $payloadZip -CompressionLevel Optimal

& dotnet publish $setupProject `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:EnableWindowsTargeting=true `
    -p:PayloadZip=$payloadZip `
    -p:PublishSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $setupBuildRoot
if ($LASTEXITCODE -ne 0) { throw 'Tek dosyalık DKC Setup.exe publish başarısız.' }

$builtSetup = Join-Path $setupBuildRoot 'DKC-Production-Print-Agent-Setup.exe'
if (-not (Test-Path -LiteralPath $builtSetup -PathType Leaf)) {
    throw 'DKC Setup.exe publish çıktısında bulunamadı.'
}
Copy-Item -LiteralPath $builtSetup -Destination $setupOutput

if ($authenticodeSigned) {
    & $signingScriptPath -FilePath $setupOutput
    if ($LASTEXITCODE -ne 0) { throw 'DKC Setup.exe Authenticode imzalama başarısız.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $setupOutput
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "DKC Setup.exe imzası doğrulanamadı: $($signature.Status)"
    }
}

$setupHash = (Get-FileHash -LiteralPath $setupOutput -Algorithm SHA256).Hash.ToLowerInvariant()
"$setupHash  DKC-Production-Print-Agent-Setup.exe" | Set-Content -LiteralPath $hashOutput -Encoding ascii

Remove-Item -LiteralPath $payloadZip -Force
Remove-Item -LiteralPath $setupBuildRoot -Recurse -Force

Write-Host "Müşteri kurulum dosyası hazır: $setupOutput"
Write-Host "SHA-256: $setupHash"
if (-not $authenticodeSigned) {
    Write-Warning 'Bu yalnız unsigned Sandbox buildidir; müşteriye dağıtmadan önce Authenticode signing zorunludur.'
}
