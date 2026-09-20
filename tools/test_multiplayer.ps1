param(
    [string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe',
    [int]$Port = 24687
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $workspace 'artifacts/multiplayer'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
foreach ($name in @('host-ready', 'step', 'done-c1', 'done-c2', 'done-c3', 'result')) {
    $file = Join-Path $artifacts ($name + '.json')
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$runs = @()
try {
    foreach ($role in @('host', 'c1', 'c2', 'c3')) {
        $logPath = Join-Path $artifacts "$role.log"
        $arguments = @('--headless', '--path', 'godot', '--log-file', ('"' + $logPath + '"'),
            '--script', 'res://tests/run.gd', '--', '--suite=multiplayer', '--smoke-test', '--no-foliage',
            "--coop-role=$role", "--coop-port=$Port")
        $process = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $runs += @{ Role = $role; Process = $process }
    }
    $deadline = (Get-Date).AddMinutes(8)
    do {
        Start-Sleep -Seconds 2
        $running = @($runs | Where-Object { -not $_.Process.HasExited })
        $failed = @($runs | Where-Object { $_.Process.HasExited -and $_.Process.ExitCode -ne 0 })
        if ($failed.Count -gt 0) { throw "A multiplayer test process failed. See $artifacts" }
        if ((Get-Date) -gt $deadline) { throw 'Multiplayer test timed out.' }
    } while ($running.Count -gt 0)
    foreach ($run in $runs) {
        $log = Get-Content -LiteralPath (Join-Path $artifacts ($run.Role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|COOP_TEST_TIMEOUT') { throw "Runtime failure in $($run.Role).log" }
        $marker = 'COOP_TEST_DONE' + '.*failures=0' # Host reports the complete assertions.
        if ($run.Role -ne 'host') { $marker = 'COOP_CLIENT_DONE' }
        if ($log -notmatch $marker) { throw "Missing completion marker in $($run.Role).log" }
    }
    Get-Content -LiteralPath (Join-Path $artifacts 'result.json')
} finally {
    foreach ($run in $runs) {
        if (-not $run.Process.HasExited) { $run.Process.Kill() }
        $run.Process.Dispose()
    }
}
