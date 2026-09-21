# RemZ / Birkenhof Nacht

First-person zombie survival, built in **Godot 4.7** (folder `godot/`). The user (Michel) does no manual work in
editors; Claude generates assets and code. Reply in German (Swiss spelling, "ss" not "ß").

## What the game is
- Autumn forest campsite at dusk, look modelled on a reference image: warm haze, leaf-covered ground, cabin,
  campfire with cauldron, log benches, pumpkins, mushrooms. Graphics quality beats framerate: the target is a
  strong gaming PC, everything runs at max settings.
- Level = the real **Waldhütte Remetschwil** (Sennhof, Heitersberg, 47.40994 N / 8.3399 E, OSM way 36785519).
  Built 1:1 from geodata, look from the user's site photos (`Fotos for map creation with annotation/`, 25 photos
  with a map inset; see the "Map" section below). The hand-drawn plans `Map_1.jpeg` / `Map_2.jpeg` are
  schematic and rotated: plan-north = real east, plan-east = real south, plan-south = real west, plan-west = real
  north. The user describes directions in the plan's frame ("Nordstrasse" = Sennhofstrasse, which really runs
  north-south on the east edge; "Wiese" is really south of the Weg zur Hütte; "Waldweg nach Hütte" comes from the
  north). Translate before touching positions.
- Systems: waves (10 + 5 n zombies times the difficulty factor, boss wave every 5th with brutes, 27 m field
  titans from wave 6 every third wave, `Waves.MAX_ACTIVE` 72), a closed palisade ring (`perimeter.gd`) whose
  only openings are the 4 barricade slots = gates (E / planner V; the player vaults a built gate with Space), the
  Waldhütte's own health (`hut_health.gd`, 5000 HP: 35 % of the zombies are "raiders" that head for its walls once
  inside the ring, every zombie within 9 m of a wall hits it, titan strikes hurt it, HUD line under the wave bar,
  minimap pulse and "ACHTUNG: DIE WALDHÜTTE WIRD ANGEGRIFFEN!"; E at a wall repairs 500 HP for 30 P; at zero the
  round is lost, `main._hut_lost` / `CoopWorld.hut_lost`; `--suite=hut_health` has 19 checks), 5 weapons with
  COD-style recoil + ADS, melee gun butt (H), grenades (G), quest tracker (Q), live round leaderboard (hold Tab), inventory (B), 6 zombie types with
  several Meshy skins each (`Zombie.TYPES[..].skins`, picked at random per zombie, missing GLBs skipped), supply drops
  from kills (ammo / grenade / medkit, walk through), kill streaks (+10 % per kill from the 3rd within 4 s, score
  popups), 4 difficulties (`GameSettings.DIFFICULTIES`, chosen in the start menu, saved), run statistics and a
  persistent top-10 table (`run_stats.gd`, `user://highscores.json`), 28 achievements, fleeing deer, procedural
  ambience (wind, fire, birds, footsteps per surface, heartbeat when low) plus recorded music/SFX, HUD with
  low-health vignette, hit-direction arcs and a wave progress bar. The start / pause / game-over menu is one
  tabbed card in `hud.gd` (Briefing, Schwierigkeit, Steuerung, Einstellungen, Bestenliste, Erfolge, Bilanz).

## Code map (`godot/scripts/`)
`main.gd` builds the whole world in `_ready` (terrain from the heightmap, road ribbons, forest via `trees.gd`,
deep-forest blocker, the two huts built from boxes with photo textures, campsite props, pasture fence, clutter,
foliage) and wires the systems. `map.gd` loads `assets/map/` (see Map) and exposes `ground_height`, cover
weights, roads, buildings, spawns, barricades. `trees.gd` procedural beech / oak / spruce (trunk meshes with
photo bark, leaf-card crowns with fake sphere normals, MultiMesh per species and 48 m cell, cylinder colliders).
`foliage.gd` PBR materials, 3-way terrain blend shader (forest floor / meadow / gravel from vertex colour),
ground leaves / grass multimeshes, falling leaves, campfire. `player.gd`, `weapons.gd`,
`grenade.gd`, `zombie.gd`, `waves.gd`, `barricade.gd`, `skills.gd`, `deer.gd`, `ambience.gd`, `sfx.gd`, `music.gd`, `hud.gd`,
`pickup.gd` (drops), `run_stats.gd` (statistics + high scores), `game_settings.gd` (profiles, difficulty, config),
`perimeter.gd` (palisade ring: `CORNERS` between the gate endpoints, log/rail MultiMeshes, collision boxes in the
`navsource` group so the navmesh only connects outside and inside through the gates; `contains()`, `points`,
`gate_edge`; `tools/plot_perimeter.py` overlays the ring on roads and terrain before touching a corner).
Scenes are built in code; `scenes/main.tscn` only holds the root. Kills are scored in `main._zombie_killed`
(difficulty multiplier, streak bonus, headshot x1.5); zombies only report through the `_on_kill` callback.

## Map (`godot/assets/map/`, generated, committed)
- `tools/geo_fetch.py` downloads swissALTI3D 0.5 m tiles (STAC), OSM (Overpass) and a swissimage WMTS mosaic
  into `input/geo/` (gitignored, ~40 MB); `tools/geo_fetch_wide.py` adds `aerial_wide.jpg` (x -480..300,
  z -300..430, 10 cm) covering Sennhof, the north edge of Remetschwil and the hamlet in the west. swissimage is
  the same imagery Google Maps shows for Switzerland, so it is the 1:1 reference for the village. `tools/build_map.py` turns them into `heightmap.f32` (float32 LE,
  1 m grid, rows = z south, cols = x east, metres relative to the fire, 659 m a.s.l.), `ground.png`
  (R forest floor, G meadow, B gravel), `map.json` (extent, roads as polylines with surface/width, hut boxes,
  campsite objects, fence lines, spawns per lane, barricade slots, 3300 tree positions with species from the
  aerial colour, shrubs) plus `tools/out/map_preview.png` and `tools/out/terrain_viewer.html` (three.js) for
  checking. All hand-tuned layout numbers live at the top of `build_map.py`; rerun it after changes. Both
  aerials are resampled to exactly 10 px per metre before the 1 m block statistics (until 19 Sep the main aerial
  was squeezed to 9 px blocks, which shifted every aerial-derived feature by up to 40 m to the south-east).
  With the wide aerial the border trees follow the real crowns (closed forest, single trees around the farms,
  nothing on the fields) and every village footprint carries `roof` (median sRGB from the aerial), `ridge`
  ("long" / "short" / "flat" from the brightness step between the two slopes) and `dark_frac` (solar panels);
  `village_buildings.gd` picks tile vs. slate, ridge axis and flat roofs from that. Farm-yard props (silage
  bales, tractor, two cars) are placed by `main._village_props` at aerial positions.
- Coordinates: x east, z south, origin = OSM picnic node 427671292 (fire is at (7, -7) after the photo analysis).
  Godot yaw = -deg_to_rad(yaw_deg) of the JSON (python rotation convention is mirrored).
- Layout facts from the photos (re-checked 19 Sep 2026 against all 25 photos and the aerial): Waldhütte =
  concrete garage storey with the garage door in the west face (north end), red board upper storey, **gable roof
  with the ridge east-west** (the gable faces the track in the west with a 1.4 m overhang on purlins and knee
  braces, eaves along the north and south faces, mossy grey tiles, small ridge vent), 12 concrete block steps
  without railing along the north face from 2.5 m east of the north-west corner up to the upper door at the east
  end, two small cellar windows in the base near the south end of the west face, east side buried in the slope.
  The fire plaza is one level gravel place (terrain flattened by the `PLAZA` polygon in `build_map.py`): four log
  benches around the square stone fire pit with swivel grill at (7, -7), picnic table on leaf litter 3 m west of
  the west bench, hollowed grey log fountain on log blocks with a thick trunk post and iron spout at the plaza's
  west edge (-2, -13), white steel drum bin on a post (-0.5, -16), info board + sign east of the Waldweg entrance
  (-5.5, -21); the Waldweg nach Hütte leaves the plaza's north-west corner at (-4, -11). Holzlager = brown
  corrugated/board walls, light fibre-cement gable roof (white in the aerial) with a 1.4 m overhang on struts on
  the road side, its ridge runs at 14 deg (not the 23 deg of the OSM outline), the big double door is 1 m from
  the south-east corner. The gravel track between the huts leads south to the fork with the Weg zur Hütte (east,
  along the forest edge with an open grass verge to the field, **no fence**, landmark oak at (66, 34)), the
  Wiesenweg (south onto the meadow, houses of Remetschwil on the horizon) and the Weg Richtung Dorf (west). The
  only fence is the wire fence on the east side of the Sennhofstrasse south of the junction. The Sennhofstrasse
  leaves the forest at the guidepost (124, 21) where the Weg zur Hütte branches off; north of it the road runs
  through dense forest on both sides. The Alps are a low band on the far horizon (sky `elevation_scale` 4.6).
  West of the Feldweg West and south of the Weg Richtung Dorf everything is farmland (the aerial classifier read
  the dark maize field as forest; `MEADOW_FORCE` now covers it), so the Weg Richtung Dorf has open fields on its
  south side all the way to the map edge. The village backdrop (`village_buildings.gd`, OSM footprints outside
  the extent) is Sennhof / Remetschwil farm style: white one- or two-storey houses under steep tile roofs, dark
  timber barns, long farmhouses with the barn under the same roof, never more than two window rows. The guidepost
  at the Waldweg entrance is procedural (`_sign_arrow`, Label3D): "Oberrohrdorf" on top points north,
  "Remetschwil" below points south.
- `tools/photo_textures.py` cuts tileable textures out of the photos into `godot/assets/textures/ph_*` (gravel,
  asphalt, forest floor, meadow, 4 barks, cladding, concrete, corrugated metal) and draws the leaf card sprites
  `assets/sprites/leaf_{beech,oak,spruce}.png` with colours sampled from the photos. Photo regions are in the
  1000 px thumbnail frame; the map inset (bottom right) must never be used.
- Godot's own PNG loader strips 16-bit, hence the raw float heightmap. `HeightMapShape3D` is the terrain
  collider; the render mesh is the full 1 m grid.

## Assets
- Meshy API (key in the file `Meshy Key` in the repo root, export it as `MESHY_API_KEY`, never print it).
  Prompts in `tools/assets.json`. `python tools/gen_asset.py <name> --pbr --polycount N` (preview + refine,
  ~6 min, runs fine with 6 in parallel) then `node tools/pack.mjs <name> --size 2048` and copy
  `public/models/<name>.glb` to `godot/assets/models/`, then `Godot.exe --headless --path godot --import`.
  `python tools/retexture.py <name> "<prompt>" <suffix>` re-textures an existing model (used to strip the
  gibberish lettering Meshy paints on crates and bins: ask for "no text, no letters"). Windows: set
  `PYTHONIOENCODING=utf-8 PYTHONUTF8=1` or the progress bar crashes.
- The Waldhütte's cladding and leaf sprites come from `tools/gen_hut_textures.py`: `ph_boards_*` (horizontal
  red-brown tongue-and-groove boards, 9 per metre, sRGB matched to photo 14) and `leaf_beech/oak.png` (1024 px
  twig clusters with veined leaves, a few yellowing). The hut roof is dark corrugated fibre cement
  (`ph_corrugated`, grey tint), not clay tiles. The leaf shader adds per-tree hue/value variation (hash of the
  crown centre), a September `autumn` yellowing on some trees and `BACKLIGHT` translucency.
- Props are Meshy models placed through `main._prop(parent, name, size, axis)`: it turns the model's longest
  horizontal extent onto local +x, scales by length (`axis` "x") or height ("y"), puts the bottom on the ground,
  applies `PROP_YAW` / `PROP_TINT` and returns null when the GLB is missing so every call site keeps its old
  box version as fallback. Models (Sep 2026): log_fountain, waste_bin, guidepost, info_board, fire_pit,
  log_bench_beam, log_picnic_table, fallen_log, workbench, ammo_crate (loot), ammo_pack / medkit (drops,
  `pickup.gd`). `tests/prop_info.gd` prints AABB and triangle counts of the GLBs; `--spawn-drops` with
  `--views=` puts the three drops on the plaza for a look.
- Meshy rigged characters are 1.7 m tall; scale by height/1.7, never by mesh AABB. Zombie skins: shambler =
  shambler/farmer/hiker/grandma, runner = runner/jogger, soldier = soldier/forester, titan = titan/colossus; a new
  skin only needs the GLB in `godot/assets/models/` plus its name in the `skins` list. `gen_asset.py` reuses the
  task state in `assets/raw/<name>/` when that folder exists: a second variant needs a new asset name. Meshy statics come as
  ~1.9-unit boxes; `Weapons._fit_height` normalises them. Weapons/animals face +X / +Z, see rotations in code.
- Trees are procedural (`trees.gd`), nothing to download. Poly Haven clutter (ferns, moss, branches) is
  optional: `python tools/fetch_polyhaven.py` + `blender -b -P tools/tree_reduce.py` into `godot/assets/trees`
  (gitignored); `main.gd` skips it when absent.
- PBR ground textures in `godot/assets/textures/` (Poly Haven), leaf/grass sprites in `godot/assets/sprites/`.
- Audio: the user's sound library lives in `C:\Users\miche\Desktop\Developement\music` (not all of it fits the
  game). Selected clips are copied to `godot/assets/audio/{music,sfx}` with clean names; `sfx.gd` maps logical
  names to file variants (random pick) and falls back to procedural bursts, `music.gd` crossfades
  title / night / morning / combat / gameover plus a "horde" layer scaled by zombies alive. The pause after a
  cleared wave picks its track from the clock (`Music.intermission_track`): 05:00-17:00 plays "morning"
  (`survived_the_night.mp3`, user's song), otherwise the night loop. The round itself still opens on "night",
  so the daylight song is only ever heard once a wave is over; the intro keeps its own track.
  `TRACKS[..].file` names the mp3 when it differs from the logical track name. `--no-music` silences it.
  After adding files run `Godot.exe --headless --path godot --import`.
- Walking through the maize is its own surface: `Sfx.STEP_SURFACES["corn"]` (bus `StepCorn`) plus the
  `_step_texture` case gives the per-step leaf swish, `Sfx.corn_bed()` the looping brush that
  `cornfield._update_rustle` fades with the player's speed while `cornfield.in_corn()` holds (silent on the
  cleared maze passages). `player._surface_step()` returns "corn" there. Checked in `--suite=range_steps`,
  which also dumps `artifacts/footsteps/corn_bed.wav` and `texture_corn.wav`.
- Bird wingbeats are not a sine: `tools/fetch_flap_library.py` downloads the animated birds of the three.js
  library (`examples/models/gltf/{Parrot,Stork}.glb`, morph flight cycles from ro.me, CC-BY), measures the
  shoulder / wrist / tip angles of every pose and bakes them into `godot/scripts/flap_cycle.gd` (32 samples per
  loop, radians, centred on the extended rest pose). `field_bird.gd` samples that - parrot for the raven, stork
  for the owl - and drives take-off burst, cruise, glide and landing from it; the curves are negated because the
  rig's roll axis points the other way. `--suite=cornfield --render-corn` renders `raven-flight` (top of the
  stroke) and `raven-downstroke`.
- Intro (`intro.gd`): after "Spiel starten" a KONM Games card with `assets/audio/music/intro.mp3`, then the
  player wakes in dense fog at the south end of the Sennhofstrasse (136, 108) and is guided by a typewriter
  briefing and a HUD arrow along waypoints to the hut. Fog and intro music fade with the distance to the hut;
  reaching the Weg zur Hütte fires `road_reached` -> wave 1 (`waves.phase == "intro"` blocks the countdown
  until then). `--no-intro` skips it (autotest, benchmark and `--view=` skip automatically), `--intro-test`
  runs it headless-ish and saves `shots/intro_wake.png` / `intro_road.png`.

## Testing
- `godot --headless --path godot --quit-after 150` catches script errors.
- Perimeter: `--suite=perimeter --smoke-test --no-intro --no-music` (headless, 17 checks: ring closed, roads only
  through gates, navmesh paths from every lane enter through a gate, sealed gates keep zombies outside and get
  attacked, a broken gate lets them in, Space vaults a built gate) and `--suite=perimeter_visual --no-intro` ->
  `shots/perimeter_*.png`. `--no-perimeter` builds the world without the ring (isolation).
- Horde checks: `Godot.exe --path godot --script res://tests/run.gd -- --suite=horde_visual --no-intro` (titan on the
  field, second skin, skin line, short titan walk -> `shots/horde_*.png`, prints HORDE_TITAN / HORDE_SKINS /
  HORDE_WALK) and `--suite=horde_bench --no-intro` (60 zombies: frozen / no shadows / anims paused / simulated FPS;
  Sep 2026 on the dev PC 148 -> 113 FPS, the horde itself is cheap). `Zombie.force_skin` pins a model for tests.
- `godot --path godot --resolution 1600x900 -- --autotest` starts the game, saves six screenshots to `shots/`
  (plaza, fountain view, fork, Weg zur Hütte, hut west face, hut north face) and quits; `--autotest --pathtest`
  instead spawns zombies on all four lanes and prints their positions after 40 s. Flags like `--no-shadows`,
  `--no-vfog`, `--no-foliage`, `--no-trees`, `--no-crowns`, `--no-trunks`, `--no-border` isolate features.
  `--views=x,z,yaw[,pitch[,hour]];...` renders several spots into `shots/view_N.png` and prints `VIEW_FPS` per
  spot (1.5 s sample, the cheapest way to benchmark a change). `--shot-ui` saves inventory, skills, pause tabs
  and the game-over screen as `shots/ui_*.png`; `--shot-menu` the start menu. `--difficulty=0..3` and
  `--quality=0..2` override the saved settings. Test runs (`--autotest`, `--smoke-test`, `--views`, `--shot-ui`)
  never write the high-score table. After regenerating `ground.png` run `Godot.exe --headless --path godot
  --import`, otherwise the game keeps the old texture. Godot.exe lives on the Desktop.
- Economy: points are the only currency. `main.KILL_VALUE` (0.6) scales the kill bounty, the wave bonus is
  20 + 6 n, quest "arrival" pays 20; the HUD shows the balance bottom-left in gold with a +/- delta popup.
  "Nochmal" / "Neue Runde" rebuild the scene and start the next round directly (`NetSession.restart_pending`
  offline, `_auto_start` for the coop host); `--suite=menu_flow --smoke-test --no-intro --no-music --no-foliage`
  checks zombie damage, death -> Nochmal, pause -> Hauptmenü and the coop restart (11 checks, ~45 s).
- `tests/range_steps.gd` (headless, `-- --smoke-test --no-intro --no-music`) checks long-range hits and the
  per-surface footsteps (`Sfx.footstep`: low-pass bus per surface + procedural texture layer; asphalt has zero
  cover weight in `ground.png`, so "all channels < 0.3" means hard ground) and dumps the step textures to
  `artifacts/footsteps/*.wav`. Weapon `range` is only the start of a 55 % damage falloff; the hit ray is 600 m.
- Other agents (a Codex/VS Code session, earlier a second Claude session) edit this working tree concurrently:
  check `git status` and mtimes before editing, patch instead of overwrite, stage only your own files.
- Pitfalls learned: SDFGI leaks through leaf cards and burns them white (keep it off, use SSIL). Flat road
  ribbons must not receive shadows, and their triangle winding must be counter-clockwise seen from above or
  they render black (back-face normals). Large Bash heredocs with Python break on Git Bash;
  write patch scripts as files instead.

## Repo hygiene
- Commit locally with the Co-Authored-By line; push only when asked. The git remote URL currently embeds a
  personal access token, the user should move to a credential manager.
