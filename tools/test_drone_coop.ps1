param([string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe', [int]$Port = 24729)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $workspace 'artifacts/drone-coop'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
foreach ($name in @('host-ready','join-late','step','done-c1','done-c2','result')) {
    $file = Join-Path $artifacts ($name + '.json')
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$runs = @()
try {
    foreach ($role in @('host','c1','c2')) {
        $argsForGodot = @('--headless','--max-fps','120','--path','godot','--log-file',(Join-Path $artifacts "$role.log"),
            '--script','res://tests/run.gd','--','--suite=drone_coop','--smoke-test','--no-intro','--no-music','--no-foliage',
            "--coop-role=$role", "--coop-port=$Port")
        $process = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $argsForGodot -WindowStyle Hidden -PassThru
        $runs += $process
    }
    $deadline = (Get-Date).AddMinutes(8)
    while (@($runs | Where-Object { -not $_.HasExited }).Count -gt 0) {
        if ((Get-Date) -gt $deadline) { throw 'Drone coop test timed out.' }
        if (@($runs | Where-Object { $_.HasExited -and $_.ExitCode -ne 0 }).Count -gt 0) { throw 'Drone coop process failed.' }
        Start-Sleep -Seconds 2
    }
    foreach ($role in @('host','c1','c2')) {
        $log = Get-Content -Raw -LiteralPath (Join-Path $artifacts "$role.log")
        if ($log -match 'SCRIPT ERROR|FAIL:|COOP_TEST_TIMEOUT') { throw "Drone coop failure: $role" }
        if ($log -notmatch 'DRONE_(COOP|CLIENT)_DONE') { throw "Missing completion: $role" }
    }
    Get-Content -LiteralPath (Join-Path $artifacts 'result.json')
} finally {
    foreach ($process in $runs) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
