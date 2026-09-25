"""New creatures of the 26 Sep 2026 batch on a small Meshy budget (105 credits at the start).

Retextures (10 credits each) of models the game already owns keep every rig, clip and hit volume:
  zombie_stag     <- stag (refine task)            the zombie deer of the crest
  zombie_spitter  <- zombie_bloater_v3 (model)     acid sacs, dripping green slime
  zombie_screamer <- zombie_nurse_v3 (model)       chalk-white skin, torn-open black mouth
  zombie_stalker  <- zombie_jogger_v3 (model)      soot-black, mud and corn husks
plus one new mesh, the farm dog (text-to-3d preview + refine, 30 credits):
  zombie_dog

Resumable: assets/raw/<name>/state.json keeps every task id. Afterwards
  node tools/pack.mjs zombie_stag --size 2048 ; node tools/pack.mjs zombie_dog --size 2048
  node tools/swap_textures.mjs zombie_spitter zombie_bloater   (rigged game GLB + the retextured maps)
The key stays in this process; it is only sent in the Authorization header to api.meshy.ai.

  python tools/creature_variants.py [names...] [--workers 5]
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

RETEX = "/openapi/v1/retexture"
T2D = "/openapi/v2/text-to-3d"
RAW = os.path.join(ROOT, "assets", "raw")

SKIN = "Photorealistic PBR game texture, no text, no logos, no painted lighting. "
JOBS = {
    "zombie_stag": {
        "kind": "retexture", "source": ("stag", "refine"), "model_file": "assets/raw/stag/model.glb",
        "prompt": SKIN + "An undead red deer stag: rotting grey-green hide with bald mangy patches, exposed "
                  "ribs and spine with dried black blood, torn ear, milky white blind eyes, dark cracked "
                  "antlers with hanging moss, mud on the legs, wounds along the flank.",
    },
    "zombie_spitter": {
        "kind": "retexture", "source": ("zombie_bloater_v3", "model"),
        "prompt": SKIN + "A bloated acid zombie: sickly yellow-green translucent skin, huge glowing acid sacs "
                  "on the throat, chest and belly that shine lime green from inside, burst boils, "
                  "dripping green slime, blackened lips and chin, torn overalls soaked in green pus.",
    },
    "zombie_screamer": {
        "kind": "retexture", "source": ("zombie_nurse_v3", "model"),
        "prompt": SKIN + "A screamer zombie: chalk-white dead skin, black veins radiating from a torn-open "
                  "gaping mouth with the jaw ripped wide, black bleeding eye sockets, bald patches, "
                  "the nurse uniform grey and shredded with dark blood down the chest.",
    },
    "zombie_stalker": {
        "kind": "retexture", "source": ("zombie_jogger_v3", "model"),
        "prompt": SKIN + "A stalker zombie that hides in a maize field: soot-black and mud-caked skin and "
                  "clothes, dried corn husks and leaves stuck all over the body, very dark matte tones, "
                  "faint pale eyes, no bright colours at all.",
    },
    "zombie_dog": {
        "kind": "text-to-3d",
        "prompt": "game asset, an undead farm dog, a large rotting German shepherd zombie dog standing on "
                  "four legs with the head low and jaws open, exposed ribs and torn skin, mangy fur, "
                  "single animal, no ground, no base, realistic proportions",
        "texture": "rotting mangy grey-brown fur with bald patches, exposed red flesh and ribs, dried black "
                   "blood around the muzzle, milky eyes, realistic PBR",
        "polycount": 14000,
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


def _download_result(folder, task):
    json.dump(task, open(os.path.join(folder, "task_result.json"), "w"), indent=2)
    download(task["model_urls"]["glb"], os.path.join(folder, "model.glb"))
    if task.get("thumbnail_url"):
        download(task["thumbnail_url"], os.path.join(folder, "thumb.png"))
    # every texture map of the first material set, for the texture swap into the rigged game GLB
    for i, maps in enumerate(task.get("texture_urls", []) or []):
        for channel, url in maps.items():
            if url:
                download(url, os.path.join(folder, "tex%d_%s.png" % (i, channel)))


def run(name):
    spec = JOBS[name]
    folder, path, state = _state(name)
    if spec["kind"] == "retexture":
        src_name, key = spec["source"]
        src = json.load(open(os.path.join(RAW, src_name, "state.json")))
        if "task" not in state:
            log("retexture", name, "from", src_name)
            payload = {"text_style_prompt": spec["prompt"], "enable_pbr": True, "enable_original_uv": True,
                       "texture_resolution": "2k", "ai_model": "latest"}
            if spec.get("model_file"):
                # the old task ids of the first-generation animals are gone from the service (404): send the file
                import base64
                data = open(os.path.join(ROOT, spec["model_file"]), "rb").read()
                payload["model_url"] = "data:model/gltf-binary;base64," + base64.b64encode(data).decode("ascii")
            else:
                payload["input_task_id"] = src[key]
            state["task"] = create_task(RETEX, payload)
            _save(path, state)
        task = poll_task(RETEX, state["task"], timeout=1200)
        _download_result(folder, task)
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
        _download_result(folder, task)
    log("DONE", name)
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--workers", type=int, default=5)
    args = ap.parse_args()
    names = args.names or list(JOBS)
    failed = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(run, n): n for n in names}
        for future in futures:
            try:
                future.result()
            except BaseException as error:  # SystemExit from the helper included
                failed.append((futures[future], repr(error)))
                log("FAILED", futures[future], repr(error))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
