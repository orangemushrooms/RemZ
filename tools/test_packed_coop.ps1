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
$previousAppData = $env:APPDATA
$profileRoot = Join-Path $workspace ('.test-user/pkc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
function Set-PackedProfile([string]$Role) {
    $env:APPDATA = Join-Path $profileRoot $Role
    $profileFolder = Join-Path $env:APPDATA 'Godot/app_userdata/RemZ'
    New-Item -ItemType Directory -Force -Path $profileFolder | Out-Null
    Set-Content -LiteralPath (Join-Path $profileFolder 'settings.cfg') -Encoding ASCII -Value "[video]`nfps_limit=60`nvsync=false`nprofile=0"
    $characters = (Join-Path $env:APPDATA 'characters').Replace('\', '/')
    [IO.File]::WriteAllText((Join-Path $profileFolder 'character.cfg'), "[profile]`ndirectory=`"$characters`"`nid=`"release_audit`"`n", [Text.UTF8Encoding]::new($false))
}
function Wait-PackedReady($Process, [string]$Marker) {
    # Stagger world loading: four concurrent model imports exceed this PC's RAM,
    # before the networking probe has even reached its first check.
    $trace = Join-Path (Split-Path $binary) ('logs/coop-' + $Process.Id + '.log')
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) { throw "Packaged player exited while loading. See $trace" }
        if ((Test-Path -LiteralPath $trace) -and (Get-Content -LiteralPath $trace -Raw) -match $Marker) { return }
        Start-Sleep -Seconds 1
    }
    throw "Packaged player did not become ready. See $trace"
}
try {
    Set-PackedProfile 'host'
    $hostArgs = @('--headless', '--max-fps', '60', '--quit-after', '14400', '--verbose', '--log-file', ('"' + (Join-Path $folder 'packed-host.log') + '"'), '--',
        '--host', "--coop-auto-start=$Players", '--port=24692', '--name=PackedHost', '--no-intro', '--character-profile=release_audit', '--class-auto-lock', '--no-foliage', '--no-music')
    $runs += Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
    Wait-PackedReady $runs[-1] 'HOST_READY'
    # Host and probe are two of the players; packaged clients fill the rest.
    $clients = @(@('PackedOne','PackedTwo') | Select-Object -First ($Players - 2))
    foreach ($name in $clients) {
        Set-PackedProfile $name
        $arguments = @('--headless', '--max-fps', '60', '--quit-after', '14400', '--log-file', ('"' + (Join-Path $folder ($name + '.log')) + '"'), '--',
            '--join=127.0.0.1', '--port=24692', "--name=$name", '--no-intro', '--character-profile=release_audit', '--class-auto-lock', '--no-foliage', '--no-music')
        $runs += Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $arguments -WindowStyle Hidden -PassThru
        Wait-PackedReady $runs[-1] 'WELCOME'
    }
    Set-PackedProfile 'probe'
    $probeArgs = @('--headless', '--max-fps', '60', '--path', 'godot', '--log-file', ('"' + (Join-Path $folder 'packed-probe.log') + '"'),
        '--script', 'res://tests/run.gd', '--', '--suite=packed_coop', '--smoke-test', '--class-auto-lock', '--no-foliage', '--no-music', "--expected-players=$Players")
    $probe = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $probeArgs -WindowStyle Hidden -PassThru
    $runs += $probe
    if (-not $probe.WaitForExit(120000)) { throw 'Packaged multiplayer probe timed out.' }
    $log = Get-Content -LiteralPath (Join-Path $folder 'packed-probe.log') -Raw
    if ($probe.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|FAIL:' -or $log -notmatch 'PACKED_COOP_DONE checks=\d+ failures=0') {
        throw 'Packaged multiplayer probe failed. See artifacts/defence/packed-probe.log.'
    }
    # Let native peers exit normally and flush their runtime logs before checking
    # them. A forced shutdown in finally is reserved for failed test runs.
    $shutdownDeadline = (Get-Date).AddMinutes(5)
    while (@($runs | Where-Object { -not $_.HasExited }).Count) {
        if ((Get-Date) -gt $shutdownDeadline) { throw 'Packaged peers did not finish their bounded run.' }
        Start-Sleep -Seconds 2
    }
    foreach ($process in $runs) {
        $process.Refresh()
        if ($process.ExitCode -ne 0) { throw "Packaged co-op process exited with $($process.ExitCode)." }
    }
    foreach ($name in @('packed-host') + $clients + @('packed-probe')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($name + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|Parse Error') { throw "Script error in packaged $name." }
        if ($log -notmatch "COOP_RUNNING players=$Players") { throw "Incomplete packaged runtime log: $name" }
        $unexpected = ($log -split "`n") | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
        if ($unexpected) { throw "Engine error in packaged $name." }
    }
    Select-String -Path (Join-Path $folder 'packed-probe.log') -Pattern 'PACKED_COOP_DONE'
} finally {
    $env:APPDATA = $previousAppData
    foreach ($process in $runs) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
