"""Downloads the open geodata for the Waldhütte Remetschwil map into input/geo/ (gitignored, ~40 MB).
  swissALTI3D 0.5 m GeoTIFF tiles (swisstopo STAC), OSM ways/nodes (Overpass), swissimage WMTS mosaic.
Usage: python tools/geo_fetch.py
"""
import os, io, json, math, requests
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "input", "geo")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "RemZ-map/1.0"}
LAT, LON = 47.4099806, 8.3397796          # OSM node 427671292, Feuerstelle = Ursprung
# local extent in metres around the origin: x east, z south
X0, X1, Z0, Z1 = -300, 150, -260, 160

def lv95(lat, lon):
    p = (lat * 3600 - 169028.66) / 10000
    l = (lon * 3600 - 26782.5) / 10000
    e = 2600072.37 + 211455.93 * l - 10938.51 * l * p - 0.36 * l * p * p - 44.54 * l ** 3
    n = 1200147.07 + 308807.95 * p + 3745.25 * l * l + 76.63 * p * p - 194.56 * l * l * p + 119.79 * p ** 3
    return e, n

E0, N0 = lv95(LAT, LON)

def dem():
    for tile in ["2667-1251", "2668-1251"]:
        p = os.path.join(OUT, f"alti_{tile}.tif")
        if os.path.exists(p):
            continue
        items = requests.get("https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissalti3d/items",
                             params={"bbox": "8.335,47.407,8.345,47.413"}, headers=UA, timeout=60).json()["features"]
        hrefs = [a["href"] for f in items for a in f["assets"].values() if tile in a["href"] and "_0.5_" in a["href"] and a["href"].endswith(".tif")]
        url = sorted(hrefs)[-1]   # newest survey year
        open(p, "wb").write(requests.get(url, headers=UA, timeout=300).content)
        print("dem", tile, url)

def osm():
    p = os.path.join(OUT, "osm.json")
    if os.path.exists(p):
        return
    q = f"""[out:json][timeout:90];
(
  way(around:600,{LAT},{LON})["highway"];
  way(around:600,{LAT},{LON})["building"];
  way(around:600,{LAT},{LON})["landuse"];
  way(around:600,{LAT},{LON})["natural"];
  way(around:600,{LAT},{LON})["waterway"];
  way(around:600,{LAT},{LON})["barrier"];
  node(around:600,{LAT},{LON})["amenity"];
  node(around:600,{LAT},{LON})["tourism"];
  node(around:600,{LAT},{LON})["natural"];
  node(around:600,{LAT},{LON})["barrier"];
  way(36785519); node(427671292);
);
out body geom;"""
    r = requests.post("https://overpass-api.de/api/interpreter", data=q.encode(), headers={**UA, "Content-Type": "text/plain"}, timeout=180)
    open(p, "w").write(r.text)
    print("osm", r.status_code)

def aerial():
    p = os.path.join(OUT, "aerial.jpg")
    if os.path.exists(p):
        return
    z = 20
    n = 2 ** z
    def merc(lat, lon):
        return (lon + 180) / 360 * n, (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n
    mpt = 40075016.686 * math.cos(math.radians(LAT)) / n     # metres per tile
    cx, cy = merc(LAT, LON)
    tx0, tx1 = int(cx + X0 / mpt), int(cx + X1 / mpt)
    ty0, ty1 = int(cy + Z0 / mpt), int(cy + Z1 / mpt)
    mos = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            r = requests.get(f"https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/{z}/{tx}/{ty}.jpeg", headers=UA, timeout=60)
            if r.status_code == 200:
                mos.paste(Image.open(io.BytesIO(r.content)), ((tx - tx0) * 256, (ty - ty0) * 256))
    ppm = 256 / mpt
    # crop to the local extent (web mercator is conformal, scale error over 500 m is negligible)
    px, py = (cx - tx0) * 256, (cy - ty0) * 256
    box = (int(px + X0 * ppm), int(py + Z0 * ppm), int(px + X1 * ppm), int(py + Z1 * ppm))
    mos.crop(box).save(p, quality=92)
    json.dump({"x0": X0, "z0": Z0, "x1": X1, "z1": Z1, "ppm": ppm}, open(os.path.join(OUT, "aerial.json"), "w"))
    print("aerial", box, ppm)

if __name__ == "__main__":
    dem(); osm(); aerial()
    print("origin LV95", E0, N0)
