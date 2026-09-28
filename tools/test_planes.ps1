param([switch]$Rendered, [switch]$RoundTrip, [switch]$Packaged)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$env:APPDATA = Join-Path $repo '.test-user'
$log = Join-Path $repo ('logs/planes-' + $(if ($Packaged) { 'packed' } elseif ($Rendered) { 'render' } else { 'headless' }) + '.log')
$engine = 'C:/Users/miche/Desktop/Godot.exe'
$script = 'res://tests/run.gd'
if ($Packaged) {
    if ($RoundTrip) { throw 'RoundTrip requires the source test suite; Packaged checks release startup.' }
    # Release templates do not support --script. Exercise the actual distributable
    # with its matching native DLLs, rather than mixing editor and release features.
    $engine = Join-Path $repo 'builds/windows/RemZ.exe'
}
$arguments = @('--max-fps','60','--log-file',('"'+$log+'"'))
if (-not $Packaged) { $arguments += @('--path','godot','--script',$script) }
else { $arguments += @('--quit-after','900') }
if (-not $Rendered) { $arguments += '--headless' }
else { $arguments += @('--windowed','--resolution','1600x900') }
$arguments += @('--','--smoke-test','--no-intro','--no-music','--quality=2','--lang=de')
if ($Packaged) { $arguments += '--explore-planes' }
else { $arguments += '--suite=planes' }
if ($Rendered -and -not $Packaged) { $arguments += '--render-planes' }
if ($RoundTrip) { $arguments += @('--planes-roundtrip','--no-foliage') }
$run = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $repo -WindowStyle Hidden -PassThru
try {
    if (-not $run.WaitForExit(240000)) { $run.Kill(); throw 'Planes test timeout.' }
    $run.Refresh()
    $content = Get-Content -LiteralPath $log -Raw
    $expected = if ($Packaged) { 'PLANES_READY trees=\d+ birds=14 crops=' } else { 'PLANES_DONE checks=\d+ failures=0' }
    if ($run.ExitCode -ne 0 -or $content -match 'SCRIPT ERROR|FAIL:' -or $content -notmatch $expected) { throw "Planes test failed: $log" }
    # The restricted desktop may deny certificate-store enumeration even for this offline map.
    $unexpected = ($content -split "`n") | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch 'Failed to read the root certificate store' }
    if ($unexpected) { throw ($unexpected -join "`n") }
    Select-String -LiteralPath $log -Pattern 'PLANES_DONE|PLANES_RENDER|PLANES_READY'
} finally { $run.Dispose() }
