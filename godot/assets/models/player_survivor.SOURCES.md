# Co-op survivor

Generated for RemZ using the project's Meshy account on 2026-09-20.
Prompt: `tools/assets.json`, entry `player_survivor`.
Reproducible/resumable pipeline: `python tools/player_asset.py`.

- Meshy 6 textured humanoid, 22,000-triangle target, rigged at 1.80 m.
- 2048 px albedo, normal and metallic/roughness maps. The packing step checks
  UV correspondence before restoring PBR maps lost by the rigging export.
- Meshy basic walking animation, packaged as `walk`.
- Runtime arm IK follows the weapon grips; the actor owns world displacement.
- Generation receipts and originals: `assets/raw/player_survivor/`.

Validation: `Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=player_avatar`.
Add `--render-avatar` and omit `--headless` to save visual checks under
`artifacts/player-avatar/`.
