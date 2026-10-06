# RemZ release audit — 6 October 2026

Network build: `remz-dev-20261006-release-audit`, protocol 8, menu version
`2026.10.06-H`. The final distributable's source revision and hashes are recorded
in its `BUILD-INFO.json` and the publication receipt.

## Corrections

- Planes: dying during exploration after stopping a survival session no longer
  dereferences the removed wave controller. Recovery restores playable controls
  and does not insert a survival record for the exploration death.
- Online host loss: EOS can report the server's peer disconnect before its
  server-disconnected notification. The client now disables the session at the
  first notification, before roster/UI callbacks can send an RPC to the closed
  connection. A deterministic regression verifies observer ordering, blocked
  commands, duplicate disconnect signals and subsequent reconnection.
- Both earthworm models: attack and recovery share the same boundary pose. The
  importer retains the authored rotation keys, preventing its optimizer from
  replacing small movements with different constant poses across clips. The
  existing meshes, skins and textures are retained. `align_worm_transition.py`
  verifies the GLB boundary and can repair it after regeneration.
- Test runners: isolated profiles, short Windows shader-cache paths, a shared
  profile only for intentional write/read restart pairs, incremental reports,
  renderer-required geometry/input suites, and explicit classic-mode wave tests.
  Multiplayer fixtures confirm classes before starting; file-based test
  coordination retries partial writes. The occupied-port negative test suppresses
  only its synchronous, expected diagnostic and immediately restores reporting.
  Native multiplayer probes use fresh, redirected character profiles and normal
  bounded shutdowns so complete release logs can be checked.
- Older fixtures now reflect current equipment delays, limb damage, class
  selection protection, weapon balance, animal animation calibration and the
  intended loading-screen fade. Animation preparation is checked against its
  actual contracts: fixed horizontal root motion, closed gait loops and preserved
  combat/death motion. These fixture corrections are not presented as game bugs.

## Completed source and display checks

| Group | Passing runs | Reported assertions |
| --- | ---: | ---: |
| Core regressions | 34 / 34 | 3,001 |
| Extended regressions | 100 / 100 | 6,277 |
| Map and mode variants | 11 / 11 | 438 |
| Rendered UI, input and geometry | 10 / 10 | 626 |
| Total | 155 / 155 | 10,342 |

Counts sum successful final runs; failed attempts were investigated and replaced
by successful corrective reruns. Suites that do not report a numeric assertion
count are included in the run count but contribute zero to the assertion total.
Initial failing matrix reports and final runner results remain under
`artifacts/expansion-tests/`; individual case logs represent their latest run.
`RELEASE_AUDIT_RESULTS.json` lists the final cases.

Coverage includes both maps, classic and expedition completion, progression,
quests, weapons and attachments, enemy hitboxes and movement, bosses, towers,
barricades, loot, trading, weather, day/night, classes, death/revival, navigation,
input focus, pause/resume, onboarding, fieldbook and the discovery props.
Rendered checks include German/English menus, 720p/1080p layouts, actual pointer
and key events, crop flattening, minimap filtering and countdown updates. The
full startup/intro/menu-return capture checks every sampled frame for white
flashes and checks opaque loading frames separately from the intended fade.

All 383 project scripts compile. The German catalogue has 2,634 entries and no
reported problems. PowerShell runner syntax and Python compilation pass.

## Restart and release-package checks

- Separate write/read processes on Forest and Planes: 14 assertions pass.
  Health, currency, ammunition, wave progress, seed, challenges, augments and
  plasma cooling state survive; Forest also retains collected/destroyed objects
  and shattered windows.
- Real ENet expedition sessions: Forest host/client 24 + 10 assertions;
  Planes host/client 29 + 16. Host-authoritative outpost occupancy and countdown,
  checkpoints, finales and shared state are exercised.
- Protocol/build compatibility: 36 assertions pass for protocol 7 rejection,
  mismatched build rejection and matching clients.
- Windows release export completes without script or export errors.
- Native `RemZ.exe` reaches the ready state on each map.
- The exact exported PCK passes 30 Forest and 38 Planes assertions, including
  the new animation boundary and exploration-recovery regressions. The external
  probe uses editor Godot with `--main-pack`; development tests are absent from
  the distributable. Native startup and packaged online tests are separate.

## Multiplayer and performance

All ten integration cases pass. In addition to the restart and expedition pairs
above, this includes the four-player Forest session (181 host assertions),
classic Planes victory/rematch (33 host + 29 client), four-player Planes late
join (14), class selection/progression/rejoin (21 + 18), worm replication (41
host assertions), drones (21 host assertions) and field trials (22 host assertions).
Every participating process must complete successfully; the corresponding
wrappers also reject unexpected engine/script errors.

The rendered shader regression passes all 18 assertions: warmed effects compile
no additional pipelines, each measured median call stays below 8 ms, real flare
shots hit, and their frame-time percentile remains within the pistol comparison
limit. The two larger benchmarks are diagnostic measurements, not assertions
of a guaranteed frame rate.

On the i7-11700 / RTX 3060 Ti, the Forest benchmark uses the Smooth profile at
1600 x 900, 0.85 render scale, with the full environment and a 144 FPS cap. All
15 stages complete without runtime errors. The moving 72-enemy horde averages
91.1 FPS. Dense combat with five towers averages 54.5 FPS; the frost stage
averages 47.4 FPS. The longest recorded frame is 207.5 ms during first use of
the searchlight tower. Building/destroying the full perimeter and simultaneous
mass deaths also produce isolated frames above 50 ms. These measurements do not
establish the cause of an individual frame spike or guarantee hitch-free play.

Planes combat uses 24 enemies at each of five locations, with a measured window
viewport of 1920 x 1009. Average rates range from 92.0 to 159.1 FPS; the p95
frame times range from 8.0 to 11.5 ms. Complete per-stage/per-view values are
included in `RELEASE_AUDIT_RESULTS.json`.

The native four-player release session passes all 15 probe assertions, including
authoritative ammo, grenades, inventory controls, NPC/weapon resources and
rejection of invalid purchases. Three native EXE processes and one external
probe participate; the native processes exit normally and their complete logs
are checked. Native map startup, the 68 PCK assertions and four-player package
checks are repeated after the final online-disconnect correction.

All three EOS relay cases pass: the source host/client verifies 12 + 4 assertions
for join codes, movement, snapshots, ping and clean leave; both native map pairs
reach a shared running round and shut down without unexpected engine/script
errors. The Planes host-loss failure found in the first attempt is corrected,
covered by four new deterministic assertions in `connection_cancel`, and verified
again in the new exported EXE on both maps. These are two identities on this
Windows PC using Epic's forced relay, not two separate physical internet
connections.

## Scope

This is automated regression, rendered capture and integration coverage on this
Windows machine (Godot 4.7.2, NVIDIA RTX 3060 Ti), plus inspection of the captured
UI and discovery props. It is not a guarantee of every hardware configuration,
every possible play sequence or subjective enjoyment. Only the known restricted
Windows root-certificate-store message is exempted from engine-error checks;
script errors and other engine errors fail the strict suite runner.

## Reproducing the audit

Run groups sequentially. Rendered/performance groups require the Windows Vulkan
renderer; online checks require the configured EOS backend and network access.
Use `--resume` only to continue one audit, not to substitute older passing runs
for a new release audit.

```text
python tools/test_expansion_batch.py
python tools/test_release_audit.py extended
python tools/test_release_audit.py variants
python tools/test_release_audit.py rendered
python tools/test_release_audit.py integration
python tools/test_network_compatibility.py
python tools/test_release_audit.py performance
python tools/test_expansion_pack.py
python tools/test_release_audit.py packaged
python tools/test_release_audit.py online
python tools/test_expansion.py compile_all
python tools/i18n.py check
python tools/align_worm_transition.py
python tools/check_release_eos.py --build builds/windows
```
