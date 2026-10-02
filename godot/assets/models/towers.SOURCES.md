# Tower weapon assets

Generated specifically for RemZ with Meshy 7.1 text-to-3D and PBR refinement on
2026-09-21. The shared platform, ladder, collision and upgrade armour are authored
in `scripts/defence_tower.gd`; the four GLBs below replace its prototype weapons.

| Asset | Preview task | PBR refine task |
|---|---|---|
| `tower_flame.glb` | `01a0c4a6-9c33-74b3-8d1a-760d2e97dc00` | `01a0c4b8-8025-76e6-9a27-f38874f34cae` |
| `tower_mortar.glb` | `01a0c4b8-8010-779c-bf28-6f8685d99b44` | `01a0c4b9-d88f-769c-89ac-8af991f833c9` |
| `tower_mg42.glb` | `01a0c4b8-8013-740d-843a-76a1513f3b97` | `01a0c4b9-9bd7-706a-befc-bf3b794373d8` |
| `tower_tesla.glb` | `01a0c4a6-9c2e-7780-aef0-6ddc97465b60` | `01a0c4b8-8013-740f-9fa0-07ad11b4ab34` |

Receipts report 25 preview + 10 refine credits per asset: 140 credits total,
including the two previews from the first attempt. Original GLBs, thumbnails,
task receipts and history remain in the workspace's `meshy_output/` directory.

Reproduction:

1. `python tools/meshy_towers.py` resumes saved tasks; prompts are in that script.
2. `node tools/prepare_towers.mjs flame mortar mg42 tesla` fits the models to the
   gun pivots, aligns each barrel with the muzzle, and reduces textures to 1024px
   WebP while retaining PBR materials.
3. Import the Godot project. Godot extracts the adjacent `tower_*_*.webp` files.

All three barrels were generated pointing along -X and are rotated onto Godot's
-Z axis. The Tesla coil remains vertical. No rigging or animation API tasks were
needed: game code rotates the weapon assemblies and produces the firing effects.


## The eight of 2 Oct 2026

Seven more assemblies the same way (text-to-3D preview with meshy-7.1, 25 credits, PBR refine, 10
credits; prompts in `tools/meshy_towers2.py`, fitted by `tools/prepare_towers2.mjs`, which measures the
barrel axis and the front end and takes an override where a drum or a pair of horns fools the rule):
`tower_rocket`, `tower_frost`, `tower_harpoon`, `tower_graviton`, `tower_sniper`, `tower_searchlight`,
`tower_siren` - 245 credits of the 260 the account held. The supply post is built from boxes and a mast
in `defence_tower.gd` instead. Receipts and originals stay in `meshy_output/20261002_*_tower-*`.
