param([string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $workspace 'artifacts/rendered-lobby'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$runs = @()
try {
    foreach ($role in @('host', 'client')) {
        $log = Join-Path $folder "$role.log"
        $arguments = @('--path', 'godot', '--log-file', ('"' + $log + '"'))
        if ($role -eq 'host') { $arguments += '--headless' }
        else { $arguments += @('--windowed', '--resolution', '640x360', '--max-fps', '30') }
        $arguments += @('--', '--port=24698', "--name=$role", '--smoke-test', '--no-foliage', '--no-music')
        if ($role -eq 'host') { $arguments += @('--host', '--coop-auto-start=2') }
        else { $arguments += '--join=127.0.0.1' }
        $runs += Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds(150)
        $marker = if ($role -eq 'host') { 'COOP_HOST_READY' } else { 'COOP_RUNNING players=2' }
        do {
            Start-Sleep -Seconds 2
            $content = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
            if ($content -match 'SCRIPT ERROR|Parse Error') { throw "Script error in $log" }
            if ($runs[-1].HasExited) { throw "$role exited before readiness" }
            if ((Get-Date) -gt $deadline) { throw "Timed out waiting for $role. See $log" }
        } while ($content -notmatch $marker)
    }
    Start-Sleep -Seconds 3
    $content = Get-Content -LiteralPath (Join-Path $folder 'client.log') -Raw
    if ($content -notmatch 'INITIAL_APPLY_DONE' -or $content -match 'SCRIPT ERROR|Parse Error') {
        throw 'Rendered client did not finish loading cleanly.'
    }
    Write-Output 'RENDERED_LOBBY_PASS: rendered client applied state, acknowledged readiness and entered play.'
} finally {
    foreach ($process in $runs) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
