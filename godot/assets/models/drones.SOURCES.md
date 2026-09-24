# Meshy attack drones

Generated for RemZ on 2026-09-24 with Meshy 7.1, 30,000 target triangles and 4K PBR refinement. Game copies use 2K WebP PBR maps.

| Model | Preview task | Refine task | Credits |
| --- | --- | --- | ---: |
| `drone_scout.glb` | `01a0d21c-7285-7331-8c23-cedcb3865714` | `01a0d21e-33ca-737c-845c-42110e9effbd` | 35 |
| `drone_viper.glb` | `01a0d21c-7286-7171-85ac-5d2669e91091` | `01a0d21e-3629-76e2-ab6c-5b159adec9d2` | 35 |
| `drone_tempest.glb` | `01a0d21c-72b9-77a7-82a1-6f18e3a0baff` | `01a0d21e-6eff-7530-a5e8-9b6c57f2e8fc` | 35 |

Total: 105 credits. Original GLBs, thumbnails, metadata and receipts are in `meshy_output/20260924_083116_drone-*/`.

Reproduce: `python tools/meshy_drones.py` (resumes saved tasks), then `node tools/prepare_drones.mjs` and import the Godot project. Flight models face Godot -Z. Animated rotor overlays, articulated gun mounts, collision, sounds and particle effects are authored in `scripts/attack_drone.gd`.
