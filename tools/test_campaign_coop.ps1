param([switch]$Online, [switch]$ForceRelay)
# Run EOS and LAN pairs sequentially: each process loads the complete world.
$ErrorActionPreference = 'Stop'
if ($ForceRelay -and -not $Online) { throw '-ForceRelay requires -Online.' }
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$folder = Join-Path $repo $(if ($Online) { 'artifacts/campaign-coop-eos' } else { 'artifacts/campaign-coop' })
New-Item -ItemType Directory -Force -Path $folder | Out-Null
foreach ($name in @('ready','round24','victory','finish')) {
    $file = Join-Path $folder $name
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$runs = @()
try {
    foreach ($role in @('host','client')) {
        $arguments = @('--headless','--max-fps','60','--path','godot','--log-file',('"' + (Join-Path $folder ($role + '.log')) + '"'),
            '--script','res://tests/run.gd','--','--suite=campaign_coop','--smoke-test','--no-intro','--no-music','--no-foliage',"--campaign-role=$role")
        if ($Online) {
            $arguments += @('--campaign-online', "--eos-cache=campaign-$role")
            if ($role -eq 'client') { $arguments += '--eos-fresh-device' }
            if ($ForceRelay) { $arguments += '--eos-force-relay' }
        }
        $runs += Start-Process -FilePath 'C:/Users/miche/Desktop/Godot.exe' -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    }
    foreach ($run in $runs) {
        if (-not $run.WaitForExit(230000)) { throw 'Campaign co-op timeout' }
        $run.Refresh()
        if ($run.ExitCode -ne 0) { throw "Campaign co-op process exited with $($run.ExitCode); see $folder" }
    }
    foreach ($role in @('host','client')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|TIMEOUT' -or $log -notmatch 'CAMPAIGN_COOP_DONE.*failures=0') { throw "Campaign co-op failed: $role" }
        Select-String -LiteralPath (Join-Path $folder ($role + '.log')) -Pattern 'CAMPAIGN_COOP_DONE'
    }
} finally {
    foreach ($run in $runs) { if (-not $run.HasExited) { $run.Kill() }; $run.Dispose() }
}
