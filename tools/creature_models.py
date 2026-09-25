"""Quadruped and prop models of the 26 Sep 2026 batch (Meshy, resumable like zombies_v3.py).

  zombie_dog_v2   the undead farm dog     design sheet (nano-banana-pro, 9) -> image-to-3d (Meshy 7.1, 35)
  zombie_stag_v2  the crest's zombie stag design sheet -> image-to-3d
  zombie_helmet   the mutation's steel helmet: text-to-3d preview + refine (meshy-6, 30)
Meshy rigs only humanoids, so the animals stay static meshes and move procedurally (zombie_beast.gd).
Afterwards: node tools/pack.mjs zombie_dog_v2 --size 2048 --as zombie_dog (and stag, helmet), copy
public/models/<name>.glb to godot/assets/models/, Godot.exe --headless --path godot --import.
The key stays in this process; it is only sent in the Authorization header to api.meshy.ai.

  python tools/creature_models.py [names...] [--stage design|model|all]
"""
import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "meshy-3d-generation", "scripts"))
os.chdir(ROOT)
from meshy_task import create_task, poll_task, download  # noqa: E402

T2I = "/openapi/v1/text-to-image"
I2D = "/openapi/v1/image-to-3d"
T2D = "/openapi/v2/text-to-3d"
RAW = os.path.join(ROOT, "assets", "raw")
STUDIO = (" Side view in profile, all four legs straight and clearly visible, whole animal centred with margin, "
          "plain uniform mid-grey studio background, soft even light, photorealistic, highly detailed, no text, "
          "no watermark.")
JOBS = {
    "zombie_dog_v2": {
        "kind": "image", "polycount": 30000,
        "prompt": "Full-body photo of an undead farm dog: a large rotting German shepherd zombie dog standing, head "
                  "slightly lowered with the jaws open and teeth bared, torn skin with the ribs exposed on the flank, "
                  "mangy grey-brown fur with bald patches, dried black blood around the muzzle, milky white eyes, "
                  "dark veins." + STUDIO,
    },
    "zombie_stag_v2": {
        "kind": "image", "polycount": 36000,
        "prompt": "Full-body photo of an undead red deer stag standing: large branching antlers, blood-red rotting "
                  "hide dripping with dark blood, the ribcage and spine exposed on the flank, torn ears, glowing "
                  "yellow eyes, rotten muzzle with the teeth showing, mud on the legs." + STUDIO,
    },
    "zombie_helmet": {
        "kind": "text", "polycount": 8000,
        "prompt": "game asset, a weathered WW2 style steel combat helmet, rounded dome with a short brim and a leather "
                  "chin strap, dented and scratched, single object, no head, no ground, no base",
        "texture": "scratched olive-grey steel with rust, dents and dried mud, worn brown leather chin strap, realistic PBR",
    },
}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def _state(name):
    folder = os.path.join(RAW, name)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "state.json")
    return folder, path, (json.load(open(path)) if os.path.exists(path) else {})


def _save(path, state):
    json.dump(state, open(path, "w"), indent=2)


def _fetch_model(folder, task, stage):
    json.dump(task, open(os.path.join(folder, "task_%s.json" % stage), "w"), indent=2)
    download(task["model_urls"]["glb"], os.path.join(folder, "model.glb"))
    if task.get("thumbnail_url"):
        download(task["thumbnail_url"], os.path.join(folder, "thumb.png"))
    views = task.get("thumbnail_urls") or {}
    if isinstance(views, dict):
        for view, url in views.items():
            if url:
                download(url, os.path.join(folder, "view_%s.png" % view))


def run(name, until):
    spec = JOBS[name]
    folder, path, state = _state(name)
    if spec["kind"] == "image":
        if "design" not in state:
            log("design", name)
            state["design"] = create_task(T2I, {"ai_model": "nano-banana-pro", "prompt": spec["prompt"], "aspect_ratio": "4:3"})
            _save(path, state)
        task = poll_task(T2I, state["design"], timeout=900)
        json.dump(task, open(os.path.join(folder, "task_design.json"), "w"), indent=2)
        urls = task.get("image_urls") or task.get("result", {}).get("image_urls") or []
        if urls and not os.path.exists(os.path.join(folder, "design.png")):
            download(urls[0], os.path.join(folder, "design.png"))
        if until == "design":
            log("DESIGN READY", name)
            return name
        if "model" not in state:
            log("model", name)
            state["model"] = create_task(I2D, {"input_task_id": state["design"], "ai_model": "meshy-7.1",
                                               "geometry_resolution": "4k", "should_remesh": True, "topology": "triangle",
                                               "target_polycount": spec["polycount"], "should_texture": True,
                                               "enable_pbr": True, "texture_resolution": "2k",
                                               "image_enhancement": False, "multi_view_thumbnails": True,
                                               "target_formats": ["glb"]})
            _save(path, state)
        task = poll_task(I2D, state["model"], timeout=1800)
        _fetch_model(folder, task, "model")
    else:
        if "preview" not in state:
            log("preview", name)
            state["preview"] = create_task(T2D, {"mode": "preview", "prompt": spec["prompt"], "ai_model": "meshy-6",
                                                 "topology": "triangle", "target_polycount": spec["polycount"],
                                                 "should_remesh": True})
            _save(path, state)
        task = poll_task(T2D, state["preview"], timeout=1200)
        json.dump(task, open(os.path.join(folder, "task_preview.json"), "w"), indent=2)
        if "refine" not in state:
            log("refine", name)
            state["refine"] = create_task(T2D, {"mode": "refine", "preview_task_id": state["preview"],
                                                "enable_pbr": True, "texture_prompt": spec["texture"]})
            _save(path, state)
        task = poll_task(T2D, state["refine"], timeout=1200)
        _fetch_model(folder, task, "refine")
    log("DONE", name)
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--stage", default="all", choices=["design", "model", "all"])
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()
    names = args.names or list(JOBS)
    failed = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(run, n, args.stage): n for n in names}
        for future in futures:
            try:
                future.result()
            except BaseException as error:
                failed.append(futures[future])
                log("FAILED", futures[future], repr(error))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
