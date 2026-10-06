param([string]$GameBinary = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$previousAppData = $env:APPDATA
$previousTestDir = $env:REMZ_FIELD_TEST_DIR
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
        $env:APPDATA = Join-Path $repo ('.test-user/field-coop-' + $role)
        $args = @('--headless','--max-fps','60','--log-file',('"' + (Join-Path $folder ($role + '.log')) + '"'))
        if (-not $GameBinary) { $args += @('--path','godot','--script','res://tests/run.gd') }
        $args += @('--','--suite=field_coop','--smoke-test','--class-auto-lock','--no-intro','--no-music','--no-foliage',"--field-role=$role")
        $runs += Start-Process -FilePath $binary -ArgumentList $args -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    }
    foreach ($run in $runs) {
        if (-not $run.WaitForExit(230000)) { throw 'Co-op timeout' }
        $run.Refresh()
        if ($run.ExitCode -ne 0) { throw "Field co-op process exited with $($run.ExitCode)" }
    }
    foreach ($role in @('host','client','late')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|TIMEOUT' -or $log -notmatch 'FIELD_(COOP_DONE.*failures=0|CLIENT_DONE)') { throw "Failed: $role" }
        $unexpected = ($log -split "`n") | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
        if ($unexpected) { throw "Engine error in field co-op: $role" }
    }
    Get-Content -LiteralPath (Join-Path $folder 'finish.json')
} finally {
    $env:APPDATA = $previousAppData
    $env:REMZ_FIELD_TEST_DIR = $previousTestDir
    foreach ($run in $runs) { if (-not $run.HasExited) { $run.Kill() }; $run.Dispose() }
}
