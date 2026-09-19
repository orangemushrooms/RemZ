"""Wide swissimage mosaic (10 cm) covering the village backdrop: Sennhof, the north edge of Remetschwil and the
hamlet west of the forest, i.e. the OSM footprints that build_map.py exports as "village". Output
input/geo/aerial_wide.jpg + aerial_wide.json (gitignored). Same projection and origin as geo_fetch.py.
Usage: python tools/geo_fetch_wide.py
"""
import os, io, json, math, requests
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "input", "geo")
UA = {"User-Agent": "RemZ-map/1.0"}
LAT, LON = 47.4099806, 8.3397796
X0, X1, Z0, Z1 = -480, 300, -300, 430

def main():
    p = os.path.join(OUT, "aerial_wide.jpg")
    z = 20
    n = 2 ** z
    def merc(lat, lon):
        return (lon + 180) / 360 * n, (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
    mpt = 40075016.686 * math.cos(math.radians(LAT)) / n
    cx, cy = merc(LAT, LON)
    tx0, tx1 = int(cx + X0 / mpt), int(cx + X1 / mpt)
    ty0, ty1 = int(cy + Z0 / mpt), int(cy + Z1 / mpt)
    mos = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    s = requests.Session()
    count = 0
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            r = s.get(f"https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/{z}/{tx}/{ty}.jpeg", headers=UA, timeout=60)
            if r.status_code == 200:
                mos.paste(Image.open(io.BytesIO(r.content)), ((tx - tx0) * 256, (ty - ty0) * 256))
                count += 1
    ppm = 256 / mpt
    px, py = (cx - tx0) * 256, (cy - ty0) * 256
    box = (int(px + X0 * ppm), int(py + Z0 * ppm), int(px + X1 * ppm), int(py + Z1 * ppm))
    mos.crop(box).save(p, quality=92)
    json.dump({"x0": X0, "z0": Z0, "x1": X1, "z1": Z1, "ppm": ppm}, open(os.path.join(OUT, "aerial_wide.json"), "w"))
    print("aerial_wide", box, ppm, "tiles", count)

if __name__ == "__main__":
    main()
