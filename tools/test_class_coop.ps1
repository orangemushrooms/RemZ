param([string]$Godot = 'C:/Users/miche/Desktop/Godot.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $repo ('artifacts/class-coop/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$env:APPDATA = Join-Path $repo '.test-user'
$runs = @()
try {
    foreach ($role in @('host','client')) {
        $arguments = @('--headless','--max-fps','60','--path','godot','--log-file',('"' + (Join-Path $folder ($role + '.log')) + '"'),
            '--script','res://tests/run.gd','--','--suite=class_coop','--smoke-test','--no-intro','--no-music','--no-foliage',"--class-role=$role",('"--class-test-folder=' + $folder + '"'))
        $runs += Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru
        Set-Content -LiteralPath (Join-Path $folder ($role + '.pid')) -Value $runs[-1].Id
    }
    foreach ($run in $runs) {
        if (-not $run.WaitForExit(230000)) { throw "Class co-op timeout; see $folder" }
        $run.Refresh()
    }
    foreach ($role in @('host','client')) {
        $log = Get-Content -LiteralPath (Join-Path $folder ($role + '.log')) -Raw
        if ($log -match 'SCRIPT ERROR|FAIL:|TIMEOUT' -or $log -notmatch 'CLASS_COOP_DONE.*failures=0') { throw "Class co-op failed: $role; see $folder" }
        Select-String -LiteralPath (Join-Path $folder ($role + '.log')) -Pattern 'CLASS_COOP_DONE'
    }
} finally {
    foreach ($run in $runs) { if (-not $run.HasExited) { $run.Kill() }; $run.Dispose() }
}
