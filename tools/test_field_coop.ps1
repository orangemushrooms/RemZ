param([string]$GameBinary = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$folder = Join-Path $repo 'artifacts/field-coop'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$env:REMZ_FIELD_TEST_DIR = $folder
$binary = if ($GameBinary) { (Resolve-Path -LiteralPath $GameBinary).Path } else { 'C:/Users/miche/Desktop/Godot.exe' }
foreach ($name in @('ready','late','step','client','finish')) {
    $file = Join-Path $folder ($name + '.json')
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}
$runs = @()
try {
    foreach ($role in @('host','client','late')) {
        $args = @('--headless','--max-fps','60','--log-file',('"' + (Join-Path $folder ($role + '.log')) + '"'))
        if (-not $GameBinary) { $args += @('--path','godot','--script','res://tests/run.gd') }
        $args += @('--','--suite=field_coop','--smoke-test','--no-intro','--no-music','--no-foliage',"--field-role=$role")
        $runs += Start-Process -FilePath $binary -ArgumentList $args -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    }
    foreach ($run in $runs) { if (-not $run.WaitForExit(230000)) { throw 'Co-op timeout' } }
    foreach ($role in @('host','client','late')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|TIMEOUT' -or $log -notmatch 'FIELD_(COOP_DONE.*failures=0|CLIENT_DONE)') { throw "Failed: $role" }
    }
    Get-Content -LiteralPath (Join-Path $folder 'finish.json')
} finally {
    foreach ($run in $runs) { if (-not $run.HasExited) { $run.Kill() }; $run.Dispose() }
}
