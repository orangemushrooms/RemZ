"""The user's Meshy web weapon exports of 30 Sep 2026 -> game GLBs (resumable, receipts in state.json).

Ten static Meshy web-app exports (0.05-1.1 M triangles, 2k JPEG maps, barrel along -X in a ~1.9 unit box)
replace four models and add six weapons. The web app's tasks are invisible to the API, so everything enters as
files under assets/raw/<model>_web/source.glb (gitignored, 2-43 MB each):

  decimate   source.glb -> model.glb          meshoptimizer edge collapse, UV atlas kept, emissive dropped
  orm        model.glb  -> model.glb          base-colour-only exports get a metallic/roughness map (albedo_orm.mjs);
                                          "orm": "force" replaces a useless Meshy map (the Nighthawk)
  bake       model.glb  -> stage_baked.glb    high-poly detail into the normal map (bake_normals.mjs --high source.glb)
  reframe    stage_baked.glb -> stage_framed.glb   melee only: blade along +Y, 0.37 m, origin at the guard
  pack       -> public/models/<model>.glb     pack.mjs (base 2k, other maps 2k, WebP 88)
  install    -> godot/assets/models/<model>.glb

Run: python tools/web_weapons.py [stage] [--only a,b] [--force]     stages: all (default) | decimate | orm | bake |
     reframe | pack | install | status | import (Godot headless import afterwards)
Then: node tools/weapon_geometry.mjs --all-weapons --bake godot/scripts/weapon_mount_data.gd
"""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "assets/raw"
PUBLIC = ROOT / "public/models"
MODELS = ROOT / "godot/assets/models"
GODOT = Path(r"C:\Users\miche\Desktop\Godot.exe")

# triangles: the view model sits 40 cm from the camera; the Meshy API weapons of Sep 2026 carry 11-20k, the
# hand-made web exports keep a little more detail. error: meshoptimizer's relative error bound - the three
# million-triangle pistols stop at 80-96k under the default 0.05, they need 0.3 to reach the target.
SPECS = {
	"deagle": {"source": "Desert_eagle.glb", "triangles": 36000, "error": 0.3},
	"pistol": {"source": "Start_Pistol.glb", "triangles": 36000, "error": 0.3},
	# Meshy's maps for the Nighthawk are unusable: the normal map averages 127,127,173 (the bake came out at
	# 50 deg mean deviation, 35 % clamped) and the metallic/roughness map says metallic 0 for an all-steel
	# pistol. It gets the albedo-derived ORM and a geometry-only bake instead.
	"nighthawk": {"source": "Nighthawk.glb", "triangles": 36000, "error": 0.3, "orm": "force", "geometry_only": True},
	"sig_p226": {"source": "SIG_P226.glb", "triangles": 28000, "error": 0.05},
	"smg": {"source": "MP5.glb", "triangles": 34000, "error": 0.05},
	"tommy_gun": {"source": "Tommy_Gun.glb", "triangles": 34000, "error": 0.05, "orm": True},
	"ar15": {"source": "AR_15.glb", "triangles": 34000, "error": 0.05, "orm": True},
	"spas12": {"source": "Spaz_12.glb", "triangles": 34000, "error": 0.05, "orm": True},
	"sawed_off": {"source": "Sawed_Off_Double_Barreled.glb", "triangles": 34000, "error": 0.05},
	# The knife is mounted without fitting (melee_models.gd): same frame and size as knife_real.glb had.
	"knife_real": {"source": "Starting_Knife.glb", "triangles": 14000, "error": 0.05,
		"reframe": ["--rotate", "0,0,-90", "--fit-axis", "y", "--fit", "0.37", "--anchor", "y=0.324", "--center", "x,z"]},
}


def folder(name):
	return RAW / f"{name}_web"


def state_path(name):
	return folder(name) / "state.json"


def load_state(name):
	p = state_path(name)
	return json.loads(p.read_text()) if p.exists() else {"model": name}


def save_state(name, state):
	state_path(name).write_text(json.dumps(state, indent=2) + "\n")


def node(*args):
	cmd = ["node"] + [str(a) for a in args]
	print("  $", " ".join(cmd[1:]))
	sys.stdout.flush()
	subprocess.run(cmd, cwd=ROOT, check=True)


def fresh(output, *inputs):
	"""True when output exists and is newer than every input."""
	if not output.exists():
		return False
	return all(output.stat().st_mtime >= i.stat().st_mtime for i in inputs if i.exists())


def stage_decimate(name, spec, force):
	src, out = folder(name) / "source.glb", folder(name) / "model.glb"
	if not src.exists():
		raise SystemExit(f"{name}: missing {src} (the user's web export {spec['source']})")
	if fresh(out, src) and not force:
		return False
	node(ROOT / "tools/decimate_glb.mjs", src, out, "--triangles", spec["triangles"], "--error", spec["error"])
	st = load_state(name)
	st["decimate"] = {"triangles": spec["triangles"], "error": spec["error"], "at": time.strftime("%Y-%m-%d %H:%M")}
	st.pop("orm", None)
	save_state(name, st)
	return True


def stage_orm(name, spec, force):
	if not spec.get("orm"):
		return False
	st = load_state(name)
	model = folder(name) / "model.glb"
	if st.get("orm") and not force:
		return False
	node(ROOT / "tools/albedo_orm.mjs", model, model, "--preview", folder(name) / "orm_preview.png", *(["--force"] if spec.get("orm") == "force" else []))
	st["orm"] = {"from": "albedo", "at": time.strftime("%Y-%m-%d %H:%M")}
	save_state(name, st)
	return True


def stage_bake(name, spec, force):
	model, src, out = folder(name) / "model.glb", folder(name) / "source.glb", folder(name) / "stage_baked.glb"
	if fresh(out, model) and not force:
		return False
	node(ROOT / "tools/bake_normals.mjs", model, out, "--high", src, "--size", 2048, *(["--geometry-only"] if spec.get("geometry_only") else []))
	st = load_state(name)
	st["bake"] = {"high": "source.glb", "size": 2048, "geometry_only": bool(spec.get("geometry_only")), "at": time.strftime("%Y-%m-%d %H:%M")}
	save_state(name, st)
	return True


def staged_input(name, spec):
	"""The file pack.mjs reads: the framed melee model or the baked one."""
	return folder(name) / ("stage_framed.glb" if spec.get("reframe") else "stage_baked.glb")


def stage_reframe(name, spec, force):
	if not spec.get("reframe"):
		return False
	src, out = folder(name) / "stage_baked.glb", folder(name) / "stage_framed.glb"
	if fresh(out, src) and not force:
		return False
	node(ROOT / "tools/reframe_glb.mjs", src, out, *spec["reframe"])
	st = load_state(name)
	st["reframe"] = {"args": spec["reframe"], "at": time.strftime("%Y-%m-%d %H:%M")}
	save_state(name, st)
	return True


def stage_pack(name, spec, force):
	staged = staged_input(name, spec)
	out = PUBLIC / f"{name}.glb"
	if fresh(out, staged) and not force:
		return False
	# pack.mjs reads assets/raw/<folder>/model.glb: hand it the staged file under that name via a scratch folder
	scratch = RAW / f"{name}_web_pack"
	scratch.mkdir(exist_ok=True)
	shutil.copyfile(staged, scratch / "model.glb")
	try:
		node(ROOT / "tools/pack.mjs", f"{name}_web_pack", "--size", 2048, "--albedo-size", 2048, "--quality", 88, "--as", name)
	finally:
		shutil.rmtree(scratch, ignore_errors=True)
	st = load_state(name)
	st["pack"] = {"size": 2048, "quality": 88, "at": time.strftime("%Y-%m-%d %H:%M")}
	save_state(name, st)
	return True


def stage_install(name, spec, force):
	src, dst = PUBLIC / f"{name}.glb", MODELS / f"{name}.glb"
	if fresh(dst, src) and not force:
		return False
	shutil.copyfile(src, dst)
	st = load_state(name)
	st["install"] = {"file": f"godot/assets/models/{name}.glb", "bytes": dst.stat().st_size, "at": time.strftime("%Y-%m-%d %H:%M")}
	save_state(name, st)
	print(f"  installed {dst.relative_to(ROOT)} ({dst.stat().st_size / 1048576:.2f} MB)")
	return True


STAGES = [("decimate", stage_decimate), ("orm", stage_orm), ("bake", stage_bake), ("reframe", stage_reframe), ("pack", stage_pack), ("install", stage_install)]


def status():
	for name in SPECS:
		st = load_state(name)
		done = [s for s, _ in STAGES if s in st or (s == "install" and (MODELS / f"{name}.glb").exists() and "install" in st)]
		print(f"{name:12s} {'source' if (folder(name) / 'source.glb').exists() else 'NO SOURCE':10s} {' '.join(done)}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("stage", nargs="?", default="all")
	ap.add_argument("--only", default="")
	ap.add_argument("--force", action="store_true")
	a = ap.parse_args()
	names = [n for n in SPECS if not a.only or n in a.only.split(",")]
	if a.stage == "status":
		status()
		return
	if a.stage == "import":
		subprocess.run([str(GODOT), "--headless", "--path", str(ROOT / "godot"), "--import"], check=False)
		return
	for name in names:
		spec = SPECS[name]
		print(f"== {name}")
		for stage, fn in STAGES:
			if a.stage not in ("all", stage):
				continue
			if fn(name, spec, a.force):
				print(f"  {stage}: done")


if __name__ == "__main__":
	main()
