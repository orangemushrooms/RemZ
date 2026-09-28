param([switch]$Online, [switch]$LateJoin)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$suffix = if ($LateJoin) { '-late' } elseif ($Online) { '-online' } else { '' }
$folder = Join-Path $repo ('artifacts/planes-coop' + $suffix)
New-Item -ItemType Directory -Force $folder | Out-Null
Get-ChildItem -LiteralPath $folder -File | Remove-Item
$roles = if ($LateJoin) { @('host','c1','c2','c3') } else { @('host','client') }
$runs = @()
try {
    foreach ($role in $roles) {
        $suite = if ($LateJoin) { 'planes_coop_late' } else { 'planes_coop' }
        $log = Join-Path $folder ($role + '.log')
        $arguments = @('--path','godot','--headless','--max-fps','60','--script','res://tests/run.gd','--log-file',('"'+$log+'"'),'--',('--suite='+$suite),'--no-music','--no-intro','--class-auto-lock','--no-foliage')
        if ($LateJoin) { $arguments += '--test-role=' + $role }
        elseif ($role -eq 'host') { $arguments += '--test-host' }
        if ($Online) {
            $arguments += @('--test-online',('--eos-cache='+$role))
            if ($role -eq 'client') { $arguments += '--eos-fresh-device' }
        }
        $process = Start-Process 'C:/Users/miche/Desktop/Godot.exe' -WorkingDirectory $repo -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $runs += @{Process=$process; Log=$log}
    }
    $deadline = (Get-Date).AddMinutes(11)
    while (@($runs | Where-Object { -not $_.Process.HasExited }).Count) {
        if ((Get-Date) -gt $deadline) { throw 'Planes multiplayer test timed out.' }
        Start-Sleep -Seconds 2
    }
    foreach ($run in $runs) {
        $log = Get-Content -LiteralPath $run.Log -Raw
        if ($run.Process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|FAIL:' -or $log -notmatch 'PLANES_(COOP|LATE)_DONE .*failures=0') { throw "Multiplayer test failed: $($run.Log)" }
        $unexpected = ($log -split "`n") | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
        if ($unexpected) { throw "Engine error: $($run.Log)" }
        Select-String -LiteralPath $run.Log -Pattern 'PLANES_(COOP|LATE)_DONE'
    }
} finally {
    foreach ($run in $runs) {
        if (-not $run.Process.HasExited) { $run.Process.Kill() }
        $run.Process.Dispose()
    }
}
