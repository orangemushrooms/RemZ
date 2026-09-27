$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$folder = Join-Path $repo 'artifacts/campaign-coop'
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
        $runs += Start-Process -FilePath 'C:/Users/miche/Desktop/Godot.exe' -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    }
    foreach ($run in $runs) { if (-not $run.WaitForExit(230000)) { throw 'Campaign co-op timeout' } }
    foreach ($role in @('host','client')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|TIMEOUT' -or $log -notmatch 'CAMPAIGN_COOP_DONE.*failures=0') { throw "Campaign co-op failed: $role" }
        Select-String -LiteralPath (Join-Path $folder ($role + '.log')) -Pattern 'CAMPAIGN_COOP_DONE'
    }
} finally {
    foreach ($run in $runs) { if (-not $run.HasExited) { $run.Kill() }; $run.Dispose() }
}
