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
- Systems: waves, 4 barricade slots (E), 5 weapons with COD-style recoil + ADS, grenades (G), skill menu (Tab),
  5 zombie types, fleeing deer, procedural ambience (wind, fire, birds) plus recorded music/SFX, HUD.

## Code map (`godot/scripts/`)
`main.gd` builds the whole world in `_ready` (terrain from the heightmap, road ribbons, forest via `trees.gd`,
deep-forest blocker, the two huts built from boxes with photo textures, campsite props, pasture fence, clutter,
foliage) and wires the systems. `map.gd` loads `assets/map/` (see Map) and exposes `ground_height`, cover
weights, roads, buildings, spawns, barricades. `trees.gd` procedural beech / oak / spruce (trunk meshes with
photo bark, leaf-card crowns with fake sphere normals, MultiMesh per species and 48 m cell, cylinder colliders).
`foliage.gd` PBR materials, 3-way terrain blend shader (forest floor / meadow / gravel from vertex colour),
ground leaves / grass multimeshes, falling leaves, campfire. `player.gd`, `weapons.gd`,
`grenade.gd`, `zombie.gd`, `waves.gd`, `barricade.gd`, `skills.gd`, `deer.gd`, `ambience.gd`, `sfx.gd`, `music.gd`, `hud.gd`.
Scenes are built in code; `scenes/main.tscn` only holds the root.

## Map (`godot/assets/map/`, generated, committed)
- `tools/geo_fetch.py` downloads swissALTI3D 0.5 m tiles (STAC), OSM (Overpass) and a swissimage WMTS mosaic
  into `input/geo/` (gitignored, ~40 MB). `tools/build_map.py` turns them into `heightmap.f32` (float32 LE,
  1 m grid, rows = z south, cols = x east, metres relative to the fire, 659 m a.s.l.), `ground.png`
  (R forest floor, G meadow, B gravel), `map.json` (extent, roads as polylines with surface/width, hut boxes,
  campsite objects, fence lines, spawns per lane, barricade slots, 3300 tree positions with species from the
  aerial colour, shrubs) plus `tools/out/map_preview.png` and `tools/out/terrain_viewer.html` (three.js) for
  checking. All hand-tuned layout numbers live at the top of `build_map.py`; rerun it after changes.
- Coordinates: x east, z south, origin = OSM picnic node 427671292 (fire is at (4, -7) after the photo analysis).
  Godot yaw = -deg_to_rad(yaw_deg) of the JSON (python rotation convention is mirrored).
- Layout facts from the photos: garage door on the hut's west face (north end), outside stair along the north
  face rising east to the upper door, east side buried in the slope (ground rises east ~8 %). Fire plaza
  (gravel) north-west of the hut, four log benches around the square stone fire pit with swivel grill, log
  picnic table west, log fountain + bin + signpost at the north track entrance. Holzlager (brown corrugated
  metal, white roof in the aerial) 20 m south-west of the hut, the gravel track between the huts leads south to
  the fork with the Weg zur Hütte (east, along the forest edge, pasture fence on the meadow side, landmark oak at
  (66, 34)), the Wiesenweg (south onto the meadow) and the Weg Richtung Dorf (west). The Sennhofstrasse leaves
  the forest at the guidepost (124, 21) where the Weg zur Hütte branches off.
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
  `--no-vfog`, `--no-foliage`, `--no-trees` isolate features. Godot.exe lives on the Desktop.
- Pitfalls learned: SDFGI leaks through leaf cards and burns them white (keep it off, use SSIL). Flat road
  ribbons must not receive shadows, and their triangle winding must be counter-clockwise seen from above or
  they render black (back-face normals). Large Bash heredocs with Python break on Git Bash;
  write patch scripts as files instead.

## Repo hygiene
- Commit locally with the Co-Authored-By line; push only when asked. The git remote URL currently embeds a
  personal access token, the user should move to a credential manager.
