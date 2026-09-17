"""Meshy asset pipeline for RemZ: text-to-3d preview -> refine -> (rig -> animations) -> download.
Usage: python tools/gen_asset.py <name> [--rig] [--anim ID:label ...] [--polycount N] [--pose t-pose]
Prompts come from tools/assets.json.
"""
import argparse, json, os, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "meshy-3d-generation", "scripts"))
os.chdir(ROOT)
from meshy_task import create_task, poll_task, download, record_task, save_thumbnail

T2D = "/openapi/v2/text-to-3d"

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--rig", action="store_true")
    ap.add_argument("--anim", action="append", default=[], help="action_id:label")
    ap.add_argument("--polycount", type=int, default=8000)
    ap.add_argument("--pose", default="")
    ap.add_argument("--height", type=float, default=1.7)
    ap.add_argument("--pbr", action="store_true")
    args = ap.parse_args()

    spec = json.load(open(os.path.join(ROOT, "tools", "assets.json")))[args.name]
    out = os.path.join(ROOT, "assets", "raw", args.name)
    os.makedirs(out, exist_ok=True)
    state_path = os.path.join(out, "state.json")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {}
    def save(): json.dump(state, open(state_path, "w"), indent=2)

    # 1. preview
    if "preview" not in state:
        payload = {"mode": "preview", "prompt": spec["prompt"], "ai_model": "meshy-6",
                   "topology": "triangle", "target_polycount": args.polycount, "should_remesh": True}
        if args.pose: payload["pose_mode"] = args.pose
        log("preview", args.name); state["preview"] = create_task(T2D, payload); save()
    task = poll_task(T2D, state["preview"], timeout=900)
    json.dump(task, open(os.path.join(out, "task_preview.json"), "w"), indent=2)

    # 2. refine
    if "refine" not in state:
        payload = {"mode": "refine", "preview_task_id": state["preview"], "enable_pbr": args.pbr,
                   "texture_prompt": spec.get("texture_prompt", ""), "texture_resolution": "2k"}
        log("refine", args.name); state["refine"] = create_task(T2D, payload); save()
    task = poll_task(T2D, state["refine"], timeout=900)
    json.dump(task, open(os.path.join(out, "task_refine.json"), "w"), indent=2)
    glb = os.path.join(out, "model.glb")
    if not os.path.exists(glb):
        download(task["model_urls"]["glb"], glb)
        if task.get("thumbnail_url"): download(task["thumbnail_url"], os.path.join(out, "thumb.png"))
    record_task(out, state["refine"], "text-to-3d", "refined", spec["prompt"], ["model.glb"])

    # 3. rig
    if args.rig:
        RIG = "/openapi/v1/rigging"
        if "rig" not in state:
            log("rig", args.name)
            state["rig"] = create_task(RIG, {"input_task_id": state["refine"], "height_meters": args.height}); save()
        task = poll_task(RIG, state["rig"], timeout=900)
        json.dump(task, open(os.path.join(out, "task_rig.json"), "w"), indent=2)
        r = task["result"]
        if not os.path.exists(os.path.join(out, "rigged.glb")):
            download(r["rigged_character_glb_url"], os.path.join(out, "rigged.glb"))
            ba = r.get("basic_animations", {})
            if ba.get("walking_glb_url"): download(ba["walking_glb_url"], os.path.join(out, "anim_walking.glb"))
            if ba.get("running_glb_url"): download(ba["running_glb_url"], os.path.join(out, "anim_running.glb"))
        # 4. animations
        ANIM = "/openapi/v1/animations"
        state.setdefault("anims", {})
        for a in args.anim:
            aid, label = a.split(":", 1)
            if label not in state["anims"]:
                log("anim", label); state["anims"][label] = create_task(ANIM, {"rig_task_id": state["rig"], "action_id": int(aid)}); save()
        for label, tid in state["anims"].items():
            dst = os.path.join(out, f"anim_{label}.glb")
            if os.path.exists(dst): continue
            task = poll_task(ANIM, tid, timeout=900)
            download(task["result"]["animation_glb_url"], dst)
    log("DONE", args.name)

if __name__ == "__main__":
    main()
