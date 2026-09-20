param([int]$Port = 24567)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$binary = Join-Path $workspace 'builds/windows/RemZ.exe'
$pack = Join-Path $workspace 'builds/windows/RemZ.pck'
if (-not (Test-Path -LiteralPath $binary) -or -not (Test-Path -LiteralPath $pack)) {
    throw 'RemZ.exe und RemZ.pck fehlen in builds/windows.'
}
$logs = Join-Path $workspace 'artifacts/local-coop'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($role in @('Host', 'Client')) {
    $connection = if ($role -eq 'Host') { '--host' } else { '--join=127.0.0.1' }
    $position = if ($role -eq 'Host') { '20,40' } else { '820,120' }
    $log = Join-Path $logs "$stamp-$role.log"
    $arguments = @('--windowed', '--resolution', '960x540', '--position', $position,
        '--log-file', ('"' + $log + '"'), '--', $connection, "--name=Local$role", "--port=$Port")
    # These are the two interactive game windows requested by the player.
    Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $arguments | Out-Null
    if ($role -eq 'Host') { Start-Sleep -Seconds 5 }
}
Write-Host 'Zwei Spielfenster gestartet. Sobald beide bereit sind, im Host auf Koop starten klicken.'
Write-Host 'Falls der Client vor dem Host fertig geladen hat: nach dessen Laden nochmals Beitreten klicken.'
Write-Host "Protokolle: $logs"
