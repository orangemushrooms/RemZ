param(
    [string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe',
    # -Packed runs builds/windows/RemZ.exe for both roles (--host-online / --join-code) instead of the test suite.
    [switch]$Packed,
    # -ForceRelay routes both processes through Epic's relay servers (the path strict NATs fall back to).
    [switch]$ForceRelay,
    [string]$GameBinary = '',
    [ValidateSet('forest', 'planes')][string]$Region = 'forest'
)
# Two processes over the real EOS backend: the host opens an online lobby, the client joins by code. Both run
# on this PC; the client starts with --eos-fresh-device so it signs in as a second device identity. Internet
# access and a complete .env (see tools/eos_config.py) are required. Logs and the coordination files land in
# artifacts/online.
$ErrorActionPreference = 'Stop'
if ($Region -eq 'planes' -and -not $Packed) { throw 'Use -Packed -Region planes, or tools/test_planes_coop.ps1 -Online for source tests.' }
$workspace = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $workspace 'artifacts/online'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
foreach ($name in @('code', 'step', 'client')) {
    $file = Join-Path $folder ($name + '.json')
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$runs = @()
try {
    if ($Packed) {
        # Use a disposable normal-game profile: --smoke-test disables the FPS cap,
        # which can make --quit-after expire before the second peer finishes loading.
        $env:APPDATA = Join-Path $workspace '.test-user/packed-online'
        $profileFolder = Join-Path $env:APPDATA 'Godot/app_userdata/RemZ'
        New-Item -ItemType Directory -Force -Path $profileFolder | Out-Null
        Set-Content -LiteralPath (Join-Path $profileFolder 'settings.cfg') -Encoding ASCII -Value "[video]`nfps_limit=60`nvsync=false`nprofile=0"
        # Character saves are portable by default, next to RemZ.exe. Redirect them
        # explicitly as well, otherwise a test profile would enter the release folder.
        $characterFolder = (Join-Path $env:APPDATA 'characters').Replace('\', '/')
        [IO.File]::WriteAllText((Join-Path $profileFolder 'character.cfg'), "[profile]`ndirectory=`"$characterFolder`"`nid=`"packed_host`"`n", [Text.UTF8Encoding]::new($false))
        # Godot buffers --log-file output until exit; the per-line flushed diagnostics file next to the exe
        # (logs/coop-<pid>.log, NetSession.trace_load) is what the checks read while both processes run.
        $binary = if ($GameBinary) { (Resolve-Path -LiteralPath $GameBinary).Path } else { Join-Path $workspace 'builds/windows/RemZ.exe' }
        $traceFolder = Join-Path (Split-Path $binary) 'logs'
        $hostLog = Join-Path $folder 'packed-host.log'
        $clientLog = Join-Path $folder 'packed-client.log'
        foreach ($log in @($hostLog, $clientLog)) { if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log } }
        # A bounded, normal shutdown flushes the release engine's buffered log.
        $hostArgs = @('--headless', '--max-fps', '60', '--quit-after', '4800', '--log-file', ('"' + $hostLog + '"'), '--',
            '--host-online', '--coop-auto-start=2', '--name=PackedHost', '--character-profile=packed_host', '--class-auto-lock', '--no-foliage', '--no-music', '--eos-cache=host')
        if ($ForceRelay) { $hostArgs += '--eos-force-relay' }
        if ($Region -eq 'planes') { $hostArgs += '--explore-planes' }
        $hostProcess = Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $hostArgs -WindowStyle Hidden -PassThru
        $runs += $hostProcess
        $hostTrace = Join-Path $traceFolder ('coop-' + $hostProcess.Id + '.log')
        $code = $null
        $deadline = (Get-Date).AddSeconds(150)
        while (-not $code -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            if (Test-Path -LiteralPath $hostTrace) {
                $match = Select-String -LiteralPath $hostTrace -Pattern 'ONLINE_CODE=([A-Z2-9]{6})' | Select-Object -First 1
                if ($match) { $code = $match.Matches[0].Groups[1].Value }
            }
            if ($hostProcess.HasExited) { throw "Packed host exited before publishing a join code. See $hostTrace" }
        }
        if (-not $code) { throw "Packed host published no join code within 150 s. See $hostTrace" }
        Write-Host "Host lobby code: $code"
        $clientArgs = @('--headless', '--max-fps', '60', '--quit-after', '4800', '--log-file', ('"' + $clientLog + '"'), '--',
            "--join-code=$code", '--name=PackedClient', '--character-profile=packed_client', '--class-auto-lock', '--no-foliage', '--no-music', '--eos-fresh-device', '--eos-cache=client')
        if ($ForceRelay) { $clientArgs += '--eos-force-relay' }
        if ($Region -eq 'planes') { $clientArgs += '--explore-planes' }
        $clientProcess = Start-Process -FilePath $binary -WorkingDirectory (Split-Path $binary) -ArgumentList $clientArgs -WindowStyle Hidden -PassThru
        $runs += $clientProcess
        $clientTrace = Join-Path $traceFolder ('coop-' + $clientProcess.Id + '.log')
        $deadline = (Get-Date).AddSeconds(180)
        $running = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $hostText = if (Test-Path -LiteralPath $hostTrace) { Get-Content -LiteralPath $hostTrace -Raw } else { '' }
            $clientText = if (Test-Path -LiteralPath $clientTrace) { Get-Content -LiteralPath $clientTrace -Raw } else { '' }
            if ($hostText -match 'ROUND_RUNNING players=2' -and $clientText -match 'ROUND_RUNNING players=2') { $running = $true; break }
            if ($clientText -match 'ONLINE_FAILED|LEAVE_BEGIN') { throw "The packed client gave up. See $clientTrace" }
            if ($runs | Where-Object { $_.HasExited }) { break }
        }
        if (-not $running) { throw "The packed host and client did not reach a shared running round. See $hostTrace and $clientTrace" }
        $shutdownDeadline = (Get-Date).AddSeconds(150)
        while (@($runs | Where-Object { -not $_.HasExited }).Count) {
            if ((Get-Date) -gt $shutdownDeadline) { throw 'Packed peers did not finish their bounded test run.' }
            Start-Sleep -Seconds 2
        }
        foreach ($process in $runs) {
            $process.Refresh()
            if ($process.ExitCode -ne 0) { throw "Packed peer exited with code $($process.ExitCode)." }
        }
        foreach ($logPath in @($hostLog, $clientLog)) {
            $text = Get-Content -LiteralPath $logPath -Raw
            if ([string]::IsNullOrWhiteSpace($text) -or $text -notmatch 'COOP_RUNNING players=2') { throw "Incomplete packaged runtime log: $logPath" }
            if ($text -match 'SCRIPT ERROR|Parse Error|does not support unreliable ordered') { throw "Runtime failure in $logPath" }
            $unexpected = ($text -split "`n") | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
            if ($unexpected) { throw ($unexpected -join "`n") }
            if ($Region -eq 'planes' -and $text -notmatch 'PLANES_SURVIVAL_READY') { throw "The packaged peer did not load Planes: $logPath" }
        }
        Write-Output "PACKED_ONLINE_COOP_OK region=$Region code=$code host=$hostTrace client=$clientTrace"
        return
    }
    foreach ($role in @('host', 'client')) {
        $logPath = Join-Path $folder "$role.log"
        $arguments = @('--headless', '--max-fps', '120', '--path', 'godot', '--log-file', ('"' + $logPath + '"'),
            '--script', 'res://tests/run.gd', '--', '--suite=online_coop', '--smoke-test', '--class-auto-lock', '--no-intro', '--no-music', '--no-foliage',
            "--online-role=$role", "--eos-cache=$role")
        if ($role -eq 'client') { $arguments += '--eos-fresh-device' }
        if ($ForceRelay) { $arguments += '--eos-force-relay' }
        $process = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $runs += $process
        if ($role -eq 'host') { Start-Sleep -Seconds 3 }
    }
    $deadline = (Get-Date).AddMinutes(6)
    do {
        Start-Sleep -Seconds 2
        $active = @($runs | Where-Object { -not $_.HasExited })
        if ((Get-Date) -gt $deadline) { throw 'Online co-op test timed out.' }
    } while ($active.Count -gt 0)
    foreach ($role in @('host', 'client')) {
        $log = Get-Content -LiteralPath (Join-Path $folder "$role.log") -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|ONLINE_COOP_TIMEOUT') { throw "Runtime failure in $role.log" }
        $marker = if ($role -eq 'host') { 'ONLINE_COOP_DONE checks=\d+ failures=0' } else { 'ONLINE_CLIENT_DONE checks=\d+ failures=0' }
        if ($log -match 'ONLINE_COOP_SKIPPED') { throw "The $role skipped: EOS runtime or credentials missing. See $role.log" }
        if ($log -notmatch $marker) { throw "Missing completion marker in $role.log" }
    }
    Select-String -Path (Join-Path $folder 'host.log') -Pattern 'ONLINE_CODE=|ONLINE_COOP_DONE|PASS: The application ping'
} finally {
    foreach ($process in $runs) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
