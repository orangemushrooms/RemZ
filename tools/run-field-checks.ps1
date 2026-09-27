param([string[]]$Suites = @('compile_all','field_update','sandbags','fortune_wheels','tower_planner','brewing','titan_phases','titan_variants','titan_horror','earthworms','forest_spirit','new_zombies','hunting','secret_night','cheat_menu','movement_sync','network_packets','smoke'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$folder = Join-Path $repo 'artifacts/field-checks'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$failed = @()
foreach ($suite in $Suites) {
    $log = Join-Path $folder ($suite + '.log')
    $arguments = @('--headless','--path',('"' + (Join-Path $repo 'godot') + '"'),'--log-file',('"' + $log + '"'),'--script','res://tests/run.gd','--',"--suite=$suite",'--smoke-test','--no-intro','--no-music','--no-foliage')
    $run = Start-Process -FilePath 'C:/Users/miche/Desktop/Godot.exe' -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    if (-not $run.WaitForExit(260000)) { $run.Kill(); $failed += $suite; Write-Output "$suite TIMEOUT"; continue }
    $text = Get-Content -LiteralPath $log -Raw
    if ($run.ExitCode -ne 0 -or $text -match 'SCRIPT ERROR|FAIL:|Parse Error' -or $text -notmatch '(_DONE|_RESULT|COMPILE_ALL|MOVEMENT_SYNC|NETWORK_PACKETS)') { $failed += $suite }
    Select-String -LiteralPath $log -Pattern 'DONE|COMPILE_ALL|FAIL:|SCRIPT ERROR|Parse Error' | ForEach-Object { Write-Output ($suite + ' ' + $_.Line) }
    $run.Dispose()
}
if ($failed.Count) { throw ('Failed suites: ' + ($failed -join ', ')) }
Write-Output 'FIELD_CHECKS_PASSED'
