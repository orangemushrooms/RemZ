"""Fetch public source data for The Planes. Cached; never replaces Forest inputs.
Run: python tools/planes_geo.py
"""
from pathlib import Path
import concurrent.futures
import json
import requests
from geo_fetch import lv95

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "input/geo/planes"
LAT, LON = 47.404384449011665, 8.335047115511859
E0, N0 = lv95(LAT, LON)
EXTENT = (-360, -370, 530, 330)  # west, north, east, south, metres
HEADERS = {"User-Agent": "RemZ-location-study/1.0"}


def fetch(url, path, **kwargs):
    if path.exists():
        return
    response = requests.get(url, headers=HEADERS, timeout=90, **kwargs)
    response.raise_for_status()
    path.write_bytes(response.content)
    print(path.name, len(response.content), flush=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = OUT / "catalog.json"
    fetch("https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissalti3d/items", catalog,
          params={"bbox": "8.319,47.395,8.351,47.415", "limit": 100})
    tiles = {}
    fine = {}
    for feature in json.loads(catalog.read_text())["features"]:
        for asset in feature["assets"].values():
            href = asset["href"]
            if not href.endswith(".tif"):
                continue
            tile = href.split("_")[-4]
            if "_2_2056_" in href and (tile not in tiles or href > tiles[tile]):
                tiles[tile] = href
            if "_0.5_2056_" in href and tile in ["2667-1250","2668-1250","2667-1251","2668-1251"] and (tile not in fine or href>fine[tile]):
                fine[tile] = href
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [pool.submit(fetch, href, OUT / ("dem_" + tile + ".tif")) for tile, href in tiles.items()]
        for job in jobs:
            job.result()
        jobs = [pool.submit(fetch, href, OUT / ("fine_" + tile + ".tif")) for tile, href in fine.items()]
        for job in jobs:
            job.result()
    fetch("https://wms.geo.admin.ch/", OUT / "aerial.jpg", params={
        "SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap",
        "LAYERS": "ch.swisstopo.swissimage", "STYLES": "", "CRS": "EPSG:2056",
        "BBOX": f"{E0-650},{N0-650},{E0+850},{N0+650}",
        "WIDTH": 2400, "HEIGHT": 2080, "FORMAT": "image/jpeg"})
    osm = OUT / "osm.json"
    if not osm.exists():
        query = f'''[out:json][timeout:60];(way(around:1200,{LAT},{LON})[highway];
        way(around:1200,{LAT},{LON})[building];way(around:1200,{LAT},{LON})[landuse];
        way(around:1200,{LAT},{LON})[natural];node(around:1000,{LAT},{LON})[natural];);out body geom;'''
        fetch("https://overpass-api.de/api/interpreter", osm, params={"data": query})
    (OUT / "sources.json").write_text(json.dumps({
        "origin_wgs84": [LAT, LON], "origin_lv95": [E0, N0],
        "dem": tiles, "fine_dem":fine, "dem_resolution_m":0.5,
        "aerial_extent": [-650, -650, 850, 650], "extent": EXTENT,
        "aerial": "https://wms.geo.admin.ch/?LAYERS=ch.swisstopo.swissimage",
        "osm": "https://www.openstreetmap.org/copyright",
        "google_reference": f"https://www.google.com/maps?q={LAT},{LON}",
    }, indent=2))
    print("LV95 origin", E0, N0)


if __name__ == "__main__":
    main()
