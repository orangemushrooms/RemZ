# First-person glove assets

Source: ValveSoftware/steamvr_unity_plugin, `Assets/SteamVR/Models/`.

- `right_glove.fbx`: `vr_glove_right_model_slim.fbx`
- `left_glove.fbx`: `vr_glove_left_model_slim.fbx`
- `glove_albedo.jpg`: `Materials/vr_glove_color.jpg`
- `glove_normal.png`: `Materials/vr_glove_normal.png`

Downloaded 2026-09-17 from https://github.com/ValveSoftware/steamvr_unity_plugin .
License notice is retained verbatim in `VALVE-LICENSE.txt` and must accompany distributed builds.
Valve explicitly permits using these example gloves in products:
https://valvesoftware.github.io/steamvr_unity_plugin/articles/intro.html

Integration changes: fitted finger poses, per-weapon placement, PBR material setup and continuous sleeves authored in `scripts/viewmodel_hands.gd`. No SteamVR runtime dependency is introduced.

## Meshy sleeve

`meshy_sleeve.glb` is derived from the Meshy hand/forearm study generated for this project on 2026-09-17 using Meshy 7 Ultra, 24,000 target triangles and 4K PBR textures.

- Preview task: `01a0b074-4f81-7283-8fca-bac01d77cd89`
- Refine task: `01a0b075-ee81-7425-84bc-cb54c678215f`
- Source and metadata: `meshy_output/20260917_194010_realistic-gloved-right-hand_01a0b074/`
- Preparation: `tools/prepare_viewmodel_sleeve.py` clips at the cuff, straightens the forearm centreline and preserves UVs, smooth normals and PBR texture pixels. The game bends this sleeve into each weapon's arm pose.

The generated model had an open hand rather than the requested grip. Its sleeve is combined with the Valve glove's finger skeleton to provide controllable weapon grips. The complete Meshy study is retained in the source directory for further editing.
