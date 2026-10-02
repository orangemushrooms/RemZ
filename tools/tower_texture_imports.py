"""Set the import flags of the extracted tower textures (2 Oct 2026) the way the first five towers have them:
VRAM compressed, the normal map (found by its colour: it averages about 128,128,250) as RGTC with the
roughness pass off, the base colour BC7. A fresh headless import leaves every WebP uncompressed. Idempotent.
  python tools/tower_texture_imports.py [kind...]
"""
import re
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "godot/assets/models"
KINDS = ["rocket", "frost", "harpoon", "graviton", "sniper", "searchlight", "siren"]


def set_param(text, key, value):
    pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    return pattern.sub("%s=%s" % (key, value), text) if pattern.search(text) else text.replace("[params]\n", "[params]\n%s=%s\n" % (key, value))


changed = 0
for kind in (sys.argv[1:] or KINDS):
    for webp in sorted(MODELS.glob("tower_%s_*.webp" % kind)):
        imp = Path(str(webp) + ".import")
        if not imp.exists():
            continue
        mean = Image.open(webp).convert("RGB").resize((64, 64)).getdata()
        r = sum(p[0] for p in mean) / 4096; g = sum(p[1] for p in mean) / 4096; b = sum(p[2] for p in mean) / 4096
        normal = abs(r - 128) < 24 and abs(g - 128) < 24 and b > 200
        text = original = imp.read_text(encoding="utf-8")
        text = set_param(text, "compress/mode", "2")
        text = set_param(text, "detect_3d/compress_to", "0")
        text = set_param(text, "compress/normal_map", "1" if normal else "0")
        text = set_param(text, "roughness/mode", "1" if normal else "0")
        text = set_param(text, "compress/high_quality", "true" if webp.name.endswith("_0.webp") and not normal else "false")
        if text != original:
            imp.write_text(text, encoding="utf-8")
            changed += 1
            print("updated", imp.name, "(normal map)" if normal else "")
print(changed, "import files changed")
