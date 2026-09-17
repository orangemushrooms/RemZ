#!/bin/bash
# Packs every finished *_v2 asset and installs it under the original model name for the game.
cd "$(dirname "$0")/.."
for d in assets/raw/*_v2; do
  n=$(basename "$d"); orig=${n%_v2}
  [ -f "$d/model.glb" ] || continue
  if [[ $n == zombie_* ]] && [ ! -f "$d/anim_death.glb" ]; then continue; fi
  node tools/pack.mjs "$n" --size 2048 >/dev/null 2>&1 && cp "public/models/$n.glb" "godot/assets/models/$orig.glb" && echo "installed $orig"
done
