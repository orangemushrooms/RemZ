param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$butler = Join-Path $repo 'builds/butler/butler.exe'
$identity = Join-Path $repo 'builds/butler/credentials'
$build = Join-Path $repo 'builds/windows'
$info = Get-Content (Join-Path $build 'BUILD-INFO.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $butler)) { throw 'Butler fehlt unter builds/butler/butler.exe.' }
if (-not (Test-Path -LiteralPath $identity)) { throw 'Zuerst Butler mit -i builds/butler/credentials login anmelden.' }
foreach ($file in $info.files) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $build $file.name) -Algorithm SHA256).Hash
    if ($hash -ne $file.sha256) { throw "Build-Pruefsumme stimmt nicht: $($file.name). BUILD-INFO.json nach dem Export aktualisieren." }
}
$pushArgs = @('-i', $identity, 'push', $build, 'keknyan/remz:windows', '--ignore', 'logs', '--ignore', 'logs/**', '--userversion', $info.build, '--if-changed')
if ($DryRun) { $pushArgs += '--dry-run' }
& $butler @pushArgs
if ($LASTEXITCODE -ne 0) { throw "Butler fehlgeschlagen (Exit $LASTEXITCODE)." }
