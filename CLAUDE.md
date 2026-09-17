# RemZ / Birkenhof Nacht

First-person zombie survival, built in **Godot 4.7** (folder `godot/`). The user (Michel) does no manual work in
editors; Claude generates assets and code. Reply in German (Swiss spelling, "ss" not "ß").

## What the game is
- Autumn forest campsite at dusk, look modelled on a reference image: warm haze, leaf-covered ground, cabin,
  campfire with cauldron, log benches, pumpkins, mushrooms. Graphics quality beats framerate: the target is a
  strong gaming PC, everything runs at max settings.
- Level layout follows the user's hand-drawn plan (`Map_1.jpeg`, `Map_2.jpeg` in the repo root) and is coded in
  `godot/scripts/map.gd` (roads as polylines, forest blocks as rects, campsite constants). The north forests are
  one continuous block; the only access from the Nordstrasse is the eastern "Weg zur Hütte". A zip of real photos
  for an exact rebuild is expected from the user; when it arrives, rebuild positions, sizes and materials from it.
- Systems: waves, 4 barricade slots (E), 5 weapons with COD-style recoil + ADS, grenades (G), skill menu (Tab),
  5 zombie types, fleeing deer, procedural ambience audio (no audio files), HUD.

## Code map (`godot/scripts/`)
`main.gd` builds the whole world in `_ready` (terrain, roads, stream, forests, buildings, campsite, clutter,
foliage) and wires the systems. `map.gd` layout + `ground_height`. `foliage.gd` PBR materials, terrain blend
shader, ground leaves / grass / canopy multimeshes, falling leaves, campfire. `player.gd`, `weapons.gd`,
`grenade.gd`, `zombie.gd`, `waves.gd`, `barricade.gd`, `skills.gd`, `deer.gd`, `ambience.gd`, `sfx.gd`, `hud.gd`.
Scenes are built in code; `scenes/main.tscn` only holds the root.

## Assets
- Meshy API (key in `.env` as `MESHY_API_KEY`, never print it). Prompts in `tools/assets.json`.
  `python tools/gen_asset.py <name> [--rig --pose t-pose --anim ID:label ...]` then
  `node tools/pack.mjs <name> --size 2048` and copy `public/models/<name>.glb` to `godot/assets/models/`.
  Windows: set `PYTHONIOENCODING=utf-8 PYTHONUTF8=1` or the progress bar crashes.
- Meshy rigged characters are 1.7 m tall; scale by height/1.7, never by mesh AABB. Meshy statics come as
  ~1.9-unit boxes; `Weapons._fit_height` normalises them. Weapons/animals face +X / +Z, see rotations in code.
- Photogrammetry trees and plants come from Poly Haven (CC0): `python tools/fetch_polyhaven.py` (2 GB into
  `godot/assets/ph`, gitignored), `python tools/autumn_leaves.py` (recolours leaves), then
  `blender -b -P tools/tree_reduce.py` (reduced GLBs into `godot/assets/trees`, gitignored, ~1 GB).
  Only `godot/assets/trees/*.glb` are needed to play.
- PBR ground textures in `godot/assets/textures/` (Poly Haven), leaf/grass sprites in `godot/assets/sprites/`.

## Testing
- `godot --headless --path godot --quit-after 150` catches script errors.
- `godot --path godot --resolution 1600x900 -- --autotest` starts the game, saves four screenshots to `shots/`
  and quits; flags like `--no-shadows`, `--no-vfog`, `--no-foliage` isolate rendering features.
- Pitfalls learned: SDFGI leaks through leaf cards and burns them white (keep it off, use SSIL). Flat road
  ribbons must not receive shadows or they render black. Large Bash heredocs with Python break on Git Bash;
  write patch scripts as files instead.

## Repo hygiene
- Commit locally with the Co-Authored-By line; push only when asked. The git remote URL currently embeds a
  personal access token, the user should move to a credential manager.
