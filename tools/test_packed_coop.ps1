param(
    [string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe',
    [string]$GameBinary = '',
    [ValidateRange(2, 4)][int]$Players = 4
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$binary = if ($GameBinary) { (Resolve-Path -LiteralPath $GameBinary).Path } else { Join-Path $workspace 'builds/windows/RemZ.exe' }
$folder = Join-Path $workspace 'artifacts/defence'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$runs = @()
try {
    $hostArgs = @('--headless', '--verbose', '--log-file', ('"' + (Join-Path $folder 'packed-host.log') + '"'), '--',
        '--host', "--coop-auto-start=$Players", '--port=24692', '--name=PackedHost', '--smoke-test', '--no-foliage', '--no-music')
    $runs += Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 4
    # Host and probe are two of the players; packaged clients fill the rest.
    $clients = @(@('PackedOne','PackedTwo') | Select-Object -First ($Players - 2))
    foreach ($name in $clients) {
        $arguments = @('--headless', '--log-file', ('"' + (Join-Path $folder ($name + '.log')) + '"'), '--',
            '--join=127.0.0.1', '--port=24692', "--name=$name", '--smoke-test', '--no-foliage', '--no-music')
        $runs += Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $arguments -WindowStyle Hidden -PassThru
    }
    $probeArgs = @('--headless', '--path', 'godot', '--log-file', ('"' + (Join-Path $folder 'packed-probe.log') + '"'),
        '--script', 'res://tests/run.gd', '--', '--suite=packed_coop', '--smoke-test', '--no-foliage', '--no-music', "--expected-players=$Players")
    $probe = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $probeArgs -WindowStyle Hidden -PassThru
    $runs += $probe
    if (-not $probe.WaitForExit(120000)) { throw 'Packaged multiplayer probe timed out.' }
    $log = Get-Content -LiteralPath (Join-Path $folder 'packed-probe.log') -Raw
    if ($probe.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|FAIL:' -or $log -notmatch 'PACKED_COOP_DONE checks=\d+ failures=0') {
        throw 'Packaged multiplayer probe failed. See artifacts/defence/packed-probe.log.'
    }
    foreach ($name in @('packed-host') + $clients) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($name + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|Parse Error') { throw "Script error in packaged $name." }
    }
    Select-String -Path (Join-Path $folder 'packed-probe.log') -Pattern 'PACKED_COOP_DONE'
} finally {
    foreach ($process in $runs) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
