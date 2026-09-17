param(
    [string]$Godot = 'C:/Users/miche/Desktop/Godot.exe',
    [ValidateSet('Smoke', 'WeaponEffects', 'Barricades', 'Atmosphere', 'DayNight', 'Benchmark', 'ExportPack', 'ExportWindows')]
    [string]$Mode = 'Smoke',
    [ValidateRange(0, 2)][int]$Quality = 0
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$project = Join-Path $workspace 'godot'
$logDir = Join-Path $workspace 'logs'
$null = New-Item -ItemType Directory -Force -Path $logDir
$log = Join-Path $logDir ('check-' + $Mode.ToLowerInvariant() + '.log')
$arguments = @('--path', ('"' + $project + '"'), '--log-file', ('"' + $log + '"'))
$marker = $null
switch ($Mode) {
    'Smoke' {
        $arguments += @('--headless', '--script', 'res://tests/smoke.gd', '--', '--smoke-test')
        $marker = 'SMOKE_DONE checks=\d+ failures=0'
    }
    'Benchmark' {
        $arguments += @('--disable-vsync', '--script', 'res://tests/benchmark.gd', '--', '--benchmark', "--quality=$Quality", '--screenshots')
        $marker = 'BENCHMARK_DONE'
    }
    'WeaponEffects' {
        $arguments += @('--script', 'res://tests/weapon_effects.gd', '--', '--smoke-test', '--render-effects')
        $marker = 'EFFECTS_DONE checks=\d+ failures=0'
    }
    'Barricades' {
        $arguments += @('--script', 'res://tests/barricades.gd', '--', '--smoke-test', '--render-barricades')
        $marker = 'BARRICADES_DONE checks=\d+ failures=0'
    }
    'Atmosphere' {
        $arguments += @('--script', 'res://tests/atmosphere.gd', '--', '--smoke-test', '--atmosphere-benchmark')
        $marker = 'ATMOSPHERE_DONE checks=\d+ failures=0'
    }
    'DayNight' {
        $arguments += @('--script', 'res://tests/day_night.gd', '--', '--smoke-test', '--no-music', '--day-night-benchmark')
        $marker = 'DAY_NIGHT_DONE checks=\d+ failures=0'
    }
    'ExportPack' {
        $output = Join-Path $workspace 'builds/windows/RemZ.pck'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output)
        $arguments += @('--headless', '--export-pack', '"Windows Desktop"', ('"' + $output + '"'))
    }
    'ExportWindows' {
        $output = Join-Path $workspace 'builds/windows/RemZ.exe'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output)
        $arguments += @('--headless', '--export-release', '"Windows Desktop"', ('"' + $output + '"'))
    }
}
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WorkingDirectory $workspace -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(240000)) {
    $process.Kill()
    throw "Godot test timed out; see $log"
}
$process.Refresh()
$contents = Get-Content -LiteralPath $log -Raw
if ($process.ExitCode -ne 0 -or $contents -match 'SCRIPT ERROR:|(?m)^ERROR:' -or ($marker -and $contents -notmatch $marker)) {
    throw "Godot check failed (exit $($process.ExitCode)); see $log"
}
if ($Mode -eq 'Benchmark') {
    Write-Output "Benchmark completed; inspect measured frame times in $log"
} else {
    Write-Output "$Mode passed. Log: $log"
}
if ($Mode -in @('ExportWindows', 'ExportPack')) {
    Copy-Item -LiteralPath (Join-Path $project 'assets/viewmodel/VALVE-LICENSE.txt') -Destination (Join-Path $workspace 'builds/windows/VALVE-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $project 'assets/viewmodel/SOURCES.md') -Destination (Join-Path $workspace 'builds/windows/HAND-ASSETS.md')
    Copy-Item -LiteralPath (Join-Path $project 'assets/sky/SOURCES.md') -Destination (Join-Path $workspace 'builds/windows/HORIZON-ASSETS.md')
}
