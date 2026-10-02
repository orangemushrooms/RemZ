# Weapon and Planes polish — 2026-10-02

- Sawed-Off: 3 rounds, 1.4 s reload, 28 damage per pellet (10 pellets). Its reserve cap stays at 60; starting reserve is 42. Tommy Gun: 70 rounds, 280 starting reserve. Two-magazine ammunition prices are 22 R and 56 R respectively, preserving the existing catalogue's damage-per-currency corridor.
- All 23 first-person firearms have explicit trigger landmarks. Index fingers are posed once after the imported skeleton enters the tree. Palm positions follow those landmarks instead of the outer magazine width. Handguns share a two-handed grip; the Tommy's support hand holds its vertical wooden foregrip. Hip, ADS and side inspection images are in `artifacts/grips/`.
- Every map uses the shared red weapon-stat bars. Scales are fixed across weapons; exact numbers remain visible above the bar limits. Shotgun damage is the sum of all pellets, and reload speed is the inverse of reload duration. Melee rows omit magazine and reload.
- The shared mod menu has separate scrolling weapon and attachment panes, explicit selection highlighting, compatible mods grouped by slot, and before/after numeric previews. Every owned firearm can be modified without equipping it. Planes initial selection and refresh signatures now include mod state.
- Grenade explosions and authoritative flare impacts ignite actual planted wheat cells. Sixteen pooled emitters, 4 m cells and four simulation ticks per second bound the work. No crop physics or individual stalk nodes are created. Existing fire status applies 12 damage per second to zombies and attributes kills to the igniting player. Burning cells last 10 seconds and spread locally; spent cells stay charred until the next run. Host snapshots include active fires and charred cells for late joiners. Construction data supplies the cell index even on headless hosts.
- Rain and thunderstorms extinguish wheat fires once the existing weather system reports actual rain. The host clears burning cells on the next fire tick, stops spreading/damage application and replicates the extinguished state. Charred wheat stays spent; grenades and flares cannot ignite new wheat during rain. Fog alone does not extinguish fire, and fresh wheat can ignite after rain ends.
- The barricade requirement displays just the next required wave (3 or 8). The Schützenhaus key no longer fails its initial probability roll; a deterministic fallback repeats the valid-ground/trunk checks. Its label is visible at 32 m, and its map marker appears within 45 m while uncollected.

## Initial release validation

Godot 4.7.2, Windows, RTX 3060 Ti. All suites passed:

| Suite | Checks |
| --- | ---: |
| `weapon_field_polish --forest` (source + rendered Windows test export, German UI) | 40 each |
| `weapon_field_polish` (Planes; source + rendered Windows test export, German UI) | 57 each |
| `planes_gameplay` | 59 |
| `weapon_mods` | 52 |
| `class_weapons` | 327 |
| `planes_coop` (two processes, host + client) | 32 + 28 |
| `packed_coop` (normal Windows EXE, two players) | 15 |

`grip_gallery` rendered all 23 firearms from three angles. Integration checks cover both currently playable maps (Forest and The Planes), the camp and secret weapon vendors, and both mod vendors. They exercise selecting and modifying a stowed Tommy or marksman rifle while the pistol stays equipped, ammunition accounting, repeated key spawns, both ignition hooks, zombie burn damage, bounded spread, reset and snapshot restoration. The two-process Planes test also verifies host-to-client fire replication, rejection of local client ignition, the existing economy/building/quest flow and rematch.

In the tested field view, 60-frame samples averaged **11.16 ms without flames / 11.15 ms with 12 active fire cells**, using the same charred crop geometry. The simulation test averaged 19.82 microseconds per tick over a spread/burnout sequence. These measurements describe this scene and machine, not every possible hardware or combat load.

Screenshots and logs: `artifacts/weapon-field-polish/` and `artifacts/planes-coop/`. The sandbox's certificate-store warning is unrelated to these offline tests; no script errors or test failures remained in the final runs. The Windows release export and EOS packaging audit passed. Network build identifier: `remz-dev-20261002-weapon-field-polish`; all peers must use the same version.

The normal Windows EXE also completed the Forest automatic gameplay/startup test (`AUTOTEST_DONE`, 66 fps sample) and loaded Planes through `PLANES_READY`; both exited with code 0. The two-player packed Forest test passed authoritative shots/ammunition, grenade replication, inventory stability and merchant rejection checks.

Four full game instances on this 16 GB machine exceeded the practical memory budget: the first packaged attempt timed out during loading, and the staggered repeat was stopped under memory pressure. The harness now staggers peer loading, but this release does **not** claim successful four-player packaged validation. The final packed test used two players; separate PCs and other hardware were not tested.

Run a suite with an isolated APPDATA directory:

```powershell
$env:APPDATA = Join-Path (Get-Location) '.test-user'
& C:/Users/miche/Desktop/Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=weapon_field_polish --smoke-test --no-intro --no-music
```

Add `--forest` to exercise Forest. Omit `--headless` to capture menus and fire visuals. Use `--suite=grip_gallery` with a renderer to regenerate the weapon inspection images. `tools/export_packed_tests.py` exports the same suites against the Windows release template, separate from the normal distributable.

## Rain follow-up validation

`weapon_field_polish` passed 72 checks in both the headless source run and the rendered Windows release test harness. Added checks cover rain and storm extinguishing, stopped emitters, retained charred cells and snapshots, blocked grenade/flare ignition, no new field burn damage to passing zombies, renewed ignition after rain ends, and fog leaving fire intact.

The two-process Planes co-op suite passed 33 host and 29 client checks, including live extinguishing replication and rematch. The normal Windows release reached `PLANES_READY` and exited with code 0. Logs: `artifacts/rain-extinguish/` and `artifacts/planes-coop/`. Export and final test runs had no script errors; the same sandbox certificate-store warning remains. Current network build identifier: `remz-dev-20261002-rain-extinguish`.
