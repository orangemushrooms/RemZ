"""Set the texture import flags of the class weapon models (30 Sep 2026) the way the Meshy API weapons have them.

A fresh headless import leaves an extracted WebP at compress/mode=0 (lossless, uncompressed in VRAM) with
detect_3d waiting for an editor that never runs here. The base colour goes to VRAM compressed BC7
(high_quality), the metallic/roughness map to BC1/BC3, the baked normal map to RGTC (compress/normal_map=1)
with the roughness-from-normal pass off. Run after every headless import of a new weapon; idempotent.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "godot/assets/models"
WEAPONS = ["sig_p226", "nighthawk", "ar15", "tommy_gun", "spas12", "sawed_off", "pistol", "smg", "deagle", "knife_real"]


def set_param(text, key, value):
    pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    if pattern.search(text):
        return pattern.sub("%s=%s" % (key, value), text)
    return text.replace("[params]\n", "[params]\n%s=%s\n" % (key, value))


changed = 0
for name in (sys.argv[1:] or WEAPONS):
    for imp in sorted(MODELS.glob(name + "_*.webp.import")):
        stem = imp.name[len(name) + 1:-len(".webp.import")]
        text = original = imp.read_text(encoding="utf-8")
        text = set_param(text, "compress/mode", "2")
        text = set_param(text, "detect_3d/compress_to", "0")
        if stem == "normal" or stem == "2" and not (MODELS / (name + "_normal.webp")).exists():
            text = set_param(text, "compress/normal_map", "1")
            text = set_param(text, "compress/high_quality", "false")
            text = set_param(text, "roughness/mode", "1")
        elif stem == "0":
            text = set_param(text, "compress/high_quality", "true")
            text = set_param(text, "compress/normal_map", "0")
            text = set_param(text, "roughness/mode", "0")
        else:
            text = set_param(text, "compress/high_quality", "false")
            text = set_param(text, "compress/normal_map", "0")
            text = set_param(text, "roughness/mode", "0")
        if text != original:
            imp.write_text(text, encoding="utf-8")
            changed += 1
            print("updated", imp.name)
print(changed, "import files changed")
