"""Generate and install two resumable Meshy battery props."""
import json
import shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from meshy_missing import CATALOG, generate
from progression_assets import authenticate, ROOT
SPECS = {
 "firework_battery_40": "Large professional consumer fireworks cake box, squat square heavy cardboard carton, open top with a dense grid of 36 upright circular brown cardboard launch tubes, 6 by 6 rows. Purple and gold star patterned wrapper, green fuse on side, believable cardboard seams. Flat bottom. No rocket sticks, no lid, no sparks, no text.",
 "firework_battery_90": "Very large wide rectangular compound fireworks battery box, heavy squat cardboard carton, open top showing 100 tightly packed upright circular brown cardboard launch tubes in rows, some outer rows angled slightly outward. Deep red black and gold star patterned wrapper, short green side fuse, realistic folded cardboard edges. Flat bottom. No rocket sticks, no lid, no sparks, no text."
}
def run(name):
 CATALOG[name] = {"prompt": SPECS[name]}
 generate(name)
 state = json.loads((ROOT / "meshy_output" / ("missing_" + name + "_state.json")).read_text())
 shutil.copy2(Path(state["folder"]) / "refine.glb", ROOT / "godot/assets/models" / (name + ".glb"))
 print("INSTALLED", name, flush=True)
if __name__ == "__main__":
 authenticate()
 with ThreadPoolExecutor(max_workers=2) as pool:
  list(pool.map(run, SPECS))
