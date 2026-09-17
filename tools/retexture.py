"""Retexture an existing Meshy model (by its refine task id) with a new style prompt.
Usage: python tools/retexture.py <name> "<texture prompt>"   -> assets/raw/<name>_autumn/model.glb
"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "meshy-3d-generation", "scripts"))
os.chdir(ROOT)
from meshy_task import create_task, poll_task, download

name, prompt = sys.argv[1], sys.argv[2]
suffix = sys.argv[3] if len(sys.argv) > 3 else "autumn"
src = json.load(open(os.path.join(ROOT, "assets", "raw", name, "state.json")))
out = os.path.join(ROOT, "assets", "raw", f"{name}_{suffix}")
os.makedirs(out, exist_ok=True)
sp = os.path.join(out, "state.json")
state = json.load(open(sp)) if os.path.exists(sp) else {}
EP = "/openapi/v1/retexture"
if "task" not in state:
    state["task"] = create_task(EP, {"input_task_id": src["refine"], "text_style_prompt": prompt, "enable_pbr": True, "enable_original_uv": True})
    json.dump(state, open(sp, "w"))
task = poll_task(EP, state["task"], timeout=900)
json.dump(task, open(os.path.join(out, "task_retexture.json"), "w"), indent=2)
download(task["model_urls"]["glb"], os.path.join(out, "model.glb"))
if task.get("thumbnail_url"):
    download(task["thumbnail_url"], os.path.join(out, "thumb.png"))
print("DONE", name, suffix)
