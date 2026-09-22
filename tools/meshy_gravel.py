"""Resumable Meshy gravel cluster for forest-road surface detail."""
import json
import shutil
from pathlib import Path
from meshy_missing import CATALOG, generate
from progression_assets import authenticate, ROOT

NAME = "forest_gravel_cluster"
CATALOG[NAME] = {"prompt": (
    "A small loose scattered cluster of 12 individual irregular crushed gravel stones, "
    "realistic angular limestone pebbles mixed with brown fieldstones, varying sizes 1 to 4 centimetres. "
    "Stones lie separately in a flat sparse horizontal arrangement with empty gaps, "
    "natural worn edges and fractured mineral surfaces. Muted grey brown earth colours. "
    "No slab, no foundation, no concrete, no rectangular outline, no large boulders.")}
if __name__ == "__main__":
    authenticate()
    generate(NAME)
    state = json.loads((ROOT / "meshy_output" / ("missing_" + NAME + "_state.json")).read_text())
    shutil.copy2(Path(state["folder"]) / "refine.glb", ROOT / "godot/assets/models/forest_gravel_cluster.glb")
    print("Installed forest_gravel_cluster.glb", flush=True)
