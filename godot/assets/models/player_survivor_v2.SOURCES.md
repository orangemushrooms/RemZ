# Reference-guided survivor, version 2

Created for RemZ on 2026-09-20 with the project's Meshy account.
Reference image generated using the built-in image_gen tool; image and exact
prompt: `assets/raw/player_survivor_v2/reference.png` and `reference-prompt.txt`.

Generation: `python tools/player_asset_v2.py`, using Meshy 7.1 Image to 3D,
2K geometry pass, a 60,000-face target, 4K PBR textures, image enhancement off,
T-pose, and humanoid rigging at 1.80 m. Receipts and settings are preserved in
`assets/raw/player_survivor_v2/`. API: https://docs.meshy.ai/en/api/image-to-3d

Packing: `node tools/pack_survivor.mjs`. Checks UV correspondence before
restoring the source albedo, normal and metal/roughness maps. Retains 4K
textures, walking and running clips. Exact counts: `packed-report.json`.

Runtime: `scripts/survivor_rig.gd`, shared by all remote co-op players.
Verification: avatar renders and grip checks using `--suite=player_avatar`;
four-peer gameplay and opening via `tools/test_multiplayer.ps1 -Intro`.

The generated rig has no finger joints. Its open palms are removed during
packing and replaced at runtime with the existing articulated viewmodel gloves
(`assets/viewmodel/VALVE-LICENSE.txt` and `SOURCES.md`). The original Meshy mesh
and all textures remain intact in the raw folder. These gloves are separate
from weapon skins and cast world shadows.
