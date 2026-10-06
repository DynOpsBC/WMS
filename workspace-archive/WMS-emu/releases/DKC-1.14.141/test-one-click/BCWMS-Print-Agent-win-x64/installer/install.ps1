param([switch]$DoNotStart)
if (-not $DoNotStart) { throw "Expected DoNotStart" }
$d = Join-Path $env:LOCALAPPDATA "Programs/BCWMS Print Agent"
New-Item -ItemType Directory -Force $d | Out-Null
Set-Content (Join-Path $d "BCWMS.PrintAgent.exe") "fixture"
