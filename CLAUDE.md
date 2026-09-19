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
- Systems: waves (boss wave every 5th with brutes), 4 barricade slots (E / planner V), 5 weapons with COD-style
  recoil + ADS, melee gun butt (Q), grenades (G), skill menu (Tab), inventory (B), 5 zombie types, supply drops
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
`pickup.gd` (drops), `run_stats.gd` (statistics + high scores), `game_settings.gd` (profiles, difficulty, config).
Scenes are built in code; `scenes/main.tscn` only holds the root. Kills are scored in `main._zombie_killed`
(difficulty multiplier, streak bonus, headshot x1.5); zombies only report through the `_on_kill` callback.

## Map (`godot/assets/map/`, generated, committed)
- `tools/geo_fetch.py` downloads swissALTI3D 0.5 m tiles (STAC), OSM (Overpass) and a swissimage WMTS mosaic
  into `input/geo/` (gitignored, ~40 MB). `tools/build_map.py` turns them into `heightmap.f32` (float32 LE,
  1 m grid, rows = z south, cols = x east, metres relative to the fire, 659 m a.s.l.), `ground.png`
  (R forest floor, G meadow, B gravel), `map.json` (extent, roads as polylines with surface/width, hut boxes,
  campsite objects, fence lines, spawns per lane, barricade slots, 3300 tree positions with species from the
  aerial colour, shrubs) plus `tools/out/map_preview.png` and `tools/out/terrain_viewer.html` (three.js) for
  checking. All hand-tuned layout numbers live at the top of `build_map.py`; rerun it after changes.
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
- `tools/photo_textures.py` cuts tileable textures out of the photos into `godot/assets/textures/ph_*` (gravel,
  asphalt, forest floor, meadow, 4 barks, cladding, concrete, corrugated metal) and draws the leaf card sprites
  `assets/sprites/leaf_{beech,oak,spruce}.png` with colours sampled from the photos. Photo regions are in the
  1000 px thumbnail frame; the map inset (bottom right) must never be used.
- Godot's own PNG loader strips 16-bit, hence the raw float heightmap. `HeightMapShape3D` is the terrain
  collider; the render mesh is the full 1 m grid.

## Assets
- Meshy API (key in `.env` as `MESHY_API_KEY`, never print it). Prompts in `tools/assets.json`.
  `python tools/gen_asset.py <name> [--rig --pose t-pose --anim ID:label ...]` then
  `node tools/pack.mjs <name> --size 2048` and copy `public/models/<name>.glb` to `godot/assets/models/`.
  Windows: set `PYTHONIOENCODING=utf-8 PYTHONUTF8=1` or the progress bar crashes.
- Meshy rigged characters are 1.7 m tall; scale by height/1.7, never by mesh AABB. Meshy statics come as
  ~1.9-unit boxes; `Weapons._fit_height` normalises them. Weapons/animals face +X / +Z, see rotations in code.
- Trees are procedural (`trees.gd`), nothing to download. Poly Haven clutter (ferns, moss, branches) is
  optional: `python tools/fetch_polyhaven.py` + `blender -b -P tools/tree_reduce.py` into `godot/assets/trees`
  (gitignored); `main.gd` skips it when absent.
- PBR ground textures in `godot/assets/textures/` (Poly Haven), leaf/grass sprites in `godot/assets/sprites/`.
- Audio: the user's sound library lives in `C:\Users\miche\Desktop\Developement\music` (not all of it fits the
  game). Selected clips are copied to `godot/assets/audio/{music,sfx}` with clean names; `sfx.gd` maps logical
  names to file variants (random pick) and falls back to procedural bursts, `music.gd` crossfades
  title / night / combat / gameover plus a "horde" layer scaled by zombies alive. `--no-music` silences it.
  After adding files run `Godot.exe --headless --path godot --import`.
- Intro (`intro.gd`): after "Spiel starten" a KONM Games card with `assets/audio/music/intro.mp3`, then the
  player wakes in dense fog at the south end of the Sennhofstrasse (136, 108) and is guided by a typewriter
  briefing and a HUD arrow along waypoints to the hut. Fog and intro music fade with the distance to the hut;
  reaching the Weg zur Hütte fires `road_reached` -> wave 1 (`waves.phase == "intro"` blocks the countdown
  until then). `--no-intro` skips it (autotest, benchmark and `--view=` skip automatically), `--intro-test`
  runs it headless-ish and saves `shots/intro_wake.png` / `intro_road.png`.

## Testing
- `godot --headless --path godot --quit-after 150` catches script errors.
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
- Other agents (a Codex/VS Code session, earlier a second Claude session) edit this working tree concurrently:
  check `git status` and mtimes before editing, patch instead of overwrite, stage only your own files.
- Pitfalls learned: SDFGI leaks through leaf cards and burns them white (keep it off, use SSIL). Flat road
  ribbons must not receive shadows, and their triangle winding must be counter-clockwise seen from above or
  they render black (back-face normals). Large Bash heredocs with Python break on Git Bash;
  write patch scripts as files instead.

## Repo hygiene
- Commit locally with the Co-Authored-By line; push only when asked. The git remote URL currently embeds a
  personal access token, the user should move to a credential manager.
