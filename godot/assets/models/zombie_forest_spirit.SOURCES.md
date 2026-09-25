# Waldgeist model

Source: `assets/raw/forest_spirit_source/Meshy_AI_Sinew_of_the_Abyss_0925164434_texture.glb` (moved out of the project on 26 Sep 2026 so the 74 MB import never reaches the pack), supplied in this project by the user.

The source GLB contains one static mesh and embedded textures. It has no skeleton or animation clips.

`tools/rig_forest_spirit.mjs` creates the game GLB locally: 16 weighted joints, eight clips (idle, walk, two melee strikes, pulse, hit, death and scream), and a reduction from 931,376 to 167,449 triangles. No paid rigging service or external animation asset is used. `forest_spirit.gd` adds the root hover, pulse warning, and bone-following shot volumes.
