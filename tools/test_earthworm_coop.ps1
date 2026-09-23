param([string]$GodotBinary = 'C:/Users/miche/Desktop/Godot.exe')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $workspace 'artifacts/earthworm-coop'
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
foreach ($name in @('ready','join-late','step','client','late','finish')) {
    $markerPath = Join-Path $outputPath ($name + '.json')
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath }
}
$runs = @()
try {
    foreach ($role in @('host','client','late')) {
        $logPath = Join-Path $outputPath ($role + '.log')
        $arguments = @('--headless','--max-fps','60','--path','godot','--log-file',('"' + $logPath + '"'),
            '--script','res://tests/run.gd','--','--suite=earthworm_coop','--smoke-test','--no-intro','--no-music','--no-foliage','--difficulty=1',"--worm-role=$role")
        $process = Start-Process -FilePath $GodotBinary -WorkingDirectory $workspace -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $runs += @{Role=$role; Process=$process}
    }
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 1
        $running = @($runs | Where-Object { -not $_.Process.HasExited })
        if ((Get-Date) -gt $deadline) { throw 'Earthworm coop test timed out.' }
    } while ($running.Count -gt 0)
    foreach ($run in $runs) {
        $log = Get-Content -LiteralPath (Join-Path $outputPath ($run.Role + '.log')) -Raw
        if ($run.Process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|FAIL:|TIMEOUT') { throw "Earthworm coop failure: $($run.Role)" }
        if ($log -notmatch 'EARTHWORM_(COOP_DONE.*failures=0|CLIENT_DONE)') { throw "Missing completion: $($run.Role)" }
    }
    Get-Content -LiteralPath (Join-Path $outputPath 'finish.json')
} finally {
    foreach ($run in $runs) {
        if (-not $run.Process.HasExited) { $run.Process.Kill() }
        $run.Process.Dispose()
    }
}
