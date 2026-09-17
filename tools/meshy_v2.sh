#!/bin/bash
# Regenerates zombies and weapons as high-detail PBR assets (v2). Key from the "Meshy Key" file, never printed.
cd "$(dirname "$0")/.."
export MESHY_API_KEY="$(tr -d '\r\n ' < "Meshy Key")" PYTHONIOENCODING=utf-8 PYTHONUTF8=1
group="$1"
if [ "$group" = "zombies" ]; then
  for n in zombie_shambler_v2 zombie_runner_v2 zombie_nurse_v2 zombie_soldier_v2 zombie_bloater_v2; do
    h=1.75; [ "$n" = "zombie_bloater_v2" ] && h=2.3
    python tools/gen_asset.py $n --rig --pose t-pose --pbr --polycount 30000 --height $h --anim 112:walk --anim 214:attack --anim 184:death || echo "FAILED $n"
  done
else
  for n in pistol_v2 revolver_v2 smg_v2 ak47_v2 rifle_v2; do
    python tools/gen_asset.py $n --pbr --polycount 20000 || echo "FAILED $n"
  done
fi
echo "GROUP_DONE $group"
