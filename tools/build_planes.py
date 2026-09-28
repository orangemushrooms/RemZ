"""Build The Planes in metres from cached swissALTI3D / OSM, with photo-authored crops.
python tools/planes_geo.py && python tools/build_planes.py
The field season, crowns and facade appearance are interpretations, not surveyed facts.
"""
import hashlib
import json
import math
from pathlib import Path
import numpy as np
import tifffile
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates
from planes_geo import OUT as GEO, ROOT, E0, N0, LAT, LON, EXTENT
from geo_fetch import lv95

OUT = ROOT / "godot/assets/planes"
X0, Z0, X1, Z1 = EXTENT
W, H = X1-X0+1, Z1-Z0+1

# User-identified underground target stand; the club confirms six 300 m targets.
# Preserve this correction on every geodata rebuild, instead of inventing housing
# from OSM's generic building=yes tag (this footprint also has layer=-1).
TARGET_STAND_OSM = 1558294553
SHOOTING_HOUSE_OSM = 118083383


def annotate_target_stand(buildings):
    house = next(b for b in buildings if b["osm_id"] == SHOOTING_HOUSE_OSM)
    points = house["poly"][:-1] if house["poly"][0] == house["poly"][-1] else house["poly"]
    facing = [round(sum(p[k] for p in points)/len(points), 3) for k in [0, 1]]
    stand = next(b for b in buildings if b["osm_id"] == TARGET_STAND_OSM)
    stand.update(kind="shooting_targets", h=2.3, collision_height=2.3, layer=-1,
                 target_count=6, facing=facing, facing_osm_id=SHOOTING_HOUSE_OSM)

# Parcel outlines traced in LV95 against the downloaded orthophoto; crop TYPES
# follow the user's summer Street View references (crops rotate between years).
FIELDS = [
    {"id": "maize_rigiweg", "kind": "corn", "poly": [[-108,12],[-164,-141],[-243,-285],[-173,-315],[-115,-322],[-58,-200],[37,-38],[0,-5]]},
    {"id": "grain_uphill", "kind": "wheat", "poly": [[44,-41],[5,-207],[54,-230],[-26,-344],[70,-360],[218,-130],[143,-33]]},
    {"id": "grain_fork_south", "kind": "wheat", "poly": [[-103,21],[0,6],[47,62],[98,78],[121,219],[47,200],[-3,175]]},
    {"id": "grain_core", "kind": "wheat", "poly": [[-263,-64],[-177,-135],[-118,12],[-245,91],[-288,31]]},
    {"id": "grain_south", "kind": "wheat", "poly": [[126,240],[274,203],[366,334],[217,329]]},
    {"id": "maize_sennhof", "kind": "corn", "poly": [[355,-115],[460,-154],[478,21],[407,33]]},
]
HEDGES = [
    [[7,8],[29,-1],[54,-5],[135,-17],[154,-22],[215,-60],[289,-102],[296,-85],[234,-38],[195,-18],[143,14],[86,29],[32,31]],
    [[167,79],[172,60],[191,53],[238,51],[270,44],[283,56],[244,72],[194,84]],
]
# Join the existing tree-row meadow all the way to the surveyed Rigiweg
# centreline. The former parallel boundary left a narrow wheat strip between
# the grass and gravel. Road masking still determines the gravel surface.
RIGIWEG_VERGE = [[-131,12],[-188,-150],[-176.51,-161.69],
                 [-170.18,-144],[-114.65,11.06],[-111.84,18.94]]


def local(g):
    e, n = lv95(g["lat"], g["lon"])
    return [round(e-E0, 2), round(N0-n, 2)]


class DEM:
    def __init__(self):
        self.tiles = []
        for path in sorted(GEO.glob("dem_*.tif"))+sorted(GEO.glob("fine_*.tif")):
            with tifffile.TiffFile(path) as file:
                meta = file.geotiff_metadata
                self.tiles.append((meta["ModelTiepoint"][3], meta["ModelTiepoint"][4], meta["ModelPixelScale"][0],file.asarray()))

    def sample(self, x, z):
        x, z = np.broadcast_arrays(np.asarray(x, float), np.asarray(z, float))
        e, n = E0+x, N0-z
        out = np.full(x.shape, np.nan)
        for left, top, cell, data in self.tiles:
            mask = (e>=left)&(e<left+1000)&(n<=top)&(n>top-1000)
            if not mask.any():
                continue
            out[mask] = map_coordinates(data, [(top-n[mask])/cell-.5, (e[mask]-left)/cell-.5], order=1, mode="nearest")
        if not np.isfinite(out).all():
            raise ValueError("DEM coverage incomplete: no invented/clamped exterior terrain allowed")
        return out


def mask(poly, scale=2):
    im = Image.new("L", (W*scale,H*scale))
    ImageDraw.Draw(im).polygon([((x-X0)*scale,(z-Z0)*scale) for x,z in poly], fill=255)
    return np.asarray(im)/255.0


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    dem = DEM()
    base = float(dem.sample(0,0))
    xx, zz = np.meshgrid(np.arange(X0,X1+1),np.arange(Z0,Z1+1))
    heights = dem.sample(xx,zz)-base
    heights.astype("<f4").tofile(OUT/"heightmap.f32")
    sx, sz = np.meshgrid(np.arange(-1000,1201,10),np.arange(-900,701,10))
    (dem.sample(sx,sz)-base).astype("<f4").tofile(OUT/"skirt.f32")
    elements = json.loads((GEO/"osm.json").read_text(encoding="utf-8"))["elements"]
    roads, buildings, woods = [], [], []
    for item in elements:
        tags = item.get("tags",{})
        poly = [local(g) for g in item.get("geometry",[])]
        if len(poly)<2:
            continue
        if "highway" in tags:
            if tags["highway"] in ["steps","proposed","construction"]:
                continue
            gravel = tags["highway"] in ["track","path","footway"]
            width = 3.2 if tags["highway"]=="track" else 1.6 if gravel else 4.5
            if item["id"] == 54857308: width = 3.4
            # The village-to-Sennhof through road is distinct from the narrow
            # field tracks. Six metres is an authored two-way carriageway width,
            # not a surveyed OSM width (the cached source has no width tag).
            if tags.get("name") == "Sennhofstrasse" and tags["highway"] == "tertiary":
                gravel = False
                width = 6.0
            roads.append({"osm_id":item["id"],"name":tags.get("name","Feldweg" if gravel else "Strasse"),
                          "surface":"gravel" if gravel else "asphalt","width":width,"pts":poly})
        # User reference: omit the isolated generic house north of Sennhof in Planes only.
        if "building" in tags:
            buildings.append({"osm_id":item["id"],"poly":poly,"h":float(tags.get("building:levels",2))*2.8})
        if tags.get("landuse")=="forest" or tags.get("natural")=="wood":
            woods.append(poly)
    for index, building in enumerate(buildings):
        building["appearance_index"] = index
    buildings = [b for b in buildings if b["osm_id"] != 36785520]
    annotate_target_stand(buildings)
    road_image = Image.new("L",(W*2,H*2))
    asphalt_image = Image.new("L",road_image.size)
    # Preserve the established vegetation RNG sequence when widening a road.
    tree_road_image = Image.new("L",road_image.size)
    for road in roads:
        target = asphalt_image if road["surface"]=="asphalt" else road_image
        draw = ImageDraw.Draw(target)
        points = [((x-X0)*2,(z-Z0)*2) for x,z in road["pts"]]
        width = round(road["width"]*2)
        draw.line(points,fill=255,width=width,joint="curve")
        for x,z in points:
            draw.ellipse((x-width/2,z-width/2,x+width/2,z+width/2),fill=255)
        if road["surface"] == "asphalt":
            seed_draw = ImageDraw.Draw(tree_road_image)
            seed_draw.line(points,fill=255,width=9,joint="curve")
            for x,z in points:
                seed_draw.ellipse((x-4.5,z-4.5,x+4.5,z+4.5),fill=255)
    gravel = np.asarray(road_image.filter(ImageFilter.GaussianBlur(.65)))/255.
    asphalt = np.asarray(asphalt_image.filter(ImageFilter.GaussianBlur(.45)))/255.
    tree_asphalt = np.asarray(tree_road_image.filter(ImageFilter.GaussianBlur(.45)))/255.
    wooded = np.zeros_like(gravel)
    for poly in HEDGES+woods: wooded = np.maximum(wooded,mask(poly))
    cover = np.stack([wooded*(1-gravel)*(1-asphalt),(1-wooded)*(1-gravel)*(1-asphalt),gravel],axis=2)
    Image.fromarray(np.uint8(cover*255)).save(OUT/"ground.png")
    crops = np.zeros((*gravel.shape,3))
    for field in FIELDS:
        crops[:,:,0 if field["kind"]=="corn" else 1] = np.maximum(crops[:,:,0 if field["kind"]=="corn" else 1], mask(field["poly"]))
    crops *= (1-np.asarray(road_image.filter(ImageFilter.MaxFilter(5)))/255.)[:,:,None]
    crops *= (1-np.asarray(asphalt_image.filter(ImageFilter.MaxFilter(11)))/255.)[:,:,None]
    crops *= (1-wooded)[:,:,None]
    # Grass ribbon around the photographed roadside tree row, west of Rigiweg.
    verge = mask(RIGIWEG_VERGE)
    crops *= (1-verge)[:,:,None]
    crops[:,:,2] = asphalt
    Image.fromarray(np.uint8(crops*255)).save(OUT/"crops.png")
    rng = np.random.default_rng(478335)
    trees = []
    # Measured row west of the junction. This row is a defining photo landmark.
    for x,z,height in [(-123,2,10),(-136,-29,10.5),(-147,-61,9),(-159,-86,10),(-169,-117,9.2)]:
        trees.append([x,z,"tree_leaf",height,float(rng.uniform(0,360))])
    # Deterministic groups restricted to actual mapped groves, keeping roads free.
    for z in range(Z0+4,Z1,6):
        for x in range(X0+4,X1,6):
            px,pz = x+rng.uniform(-2,2),z+rng.uniform(-2,2)
            i,j = int((px-X0)*2),int((pz-Z0)*2)
            if wooded[j,i]<.5 or gravel[max(0,j-7):j+8,max(0,i-7):i+8].max()>.1 or tree_asphalt[j,i]>.1:
                continue
            tree = [round(px,2),round(pz,2),"tree_leaf",round(float(rng.uniform(11,18)),2),float(rng.uniform(0,360))]
            if asphalt[j,i]<=.1: trees.append(tree)
    for item in elements:
        if item.get("tags",{}).get("natural")=="tree" and "lat" in item:
            x,z = local(item)
            if X0<x<X1 and Z0<z<Z1 and math.hypot(x+121,z-2)>14:
                trees.append([x,z,"tree_leaf",float(rng.uniform(8,13)),float(rng.uniform(0,360))])
    # Photo-directed northeast skyline, outside the playable fields. Separate RNG
    # preserves every existing foreground tree and plant placement.
    horizon_rng = np.random.default_rng(478336)
    horizon_trees = []
    for x in range(230, 931, 14):
        front = -540 + (x-230)*0.20
        for row in range(4):
            px = float(x+horizon_rng.uniform(-6,6))
            pz = float(front-row*16+horizon_rng.uniform(-7,7))
            horizon_trees.append([round(px,2),round(pz,2),
                                  round(float(horizon_rng.uniform(16,24)),2),
                                  round(float(horizon_rng.uniform(0,360)),2)])
    # Keep the field camp and its traders clear of tree trunks.
    trees = [t for t in trees if all(math.hypot(t[0]-x,t[1]-z)>4.0
             for x,z in [(22,3),(27,13),(18,11),(151,-7)])]
    data = {"region":"planes","origin_wgs84":[LAT,LON],"origin_lv95":[E0,N0],"altitude_m":base,
            "x0":X0,"z0":Z0,"w":W,"h":H,"skirt":{"x0":-1000,"z0":-900,"w":221,"h":161,"cell":10},
            "roads":roads,"buildings":{},"clearing":[],"fire":[0,0],"benches":[],"table":[0,0,0],
            "fountain":[0,0,0],"bin":[0,0],"signpost":[0,0],"log_seat":[0,0,0],"landmark_oak":[-121,2],
            "fence":[],"trees":[],"shrubs":[],"village":buildings,"player_start":[-107,18],
            "bounds":[X0+8,Z0+8,X1-X0-16,Z1-Z0-16],"barricades":[],"spawns":{},
            "fields":FIELDS,"groves":HEDGES,"landscape_trees":trees,"horizon_trees":horizon_trees,
            "views":[{"id":"sennhof","pos":[-97,15],"target":[110,-17]},
                     {"id":"junction","pos":[-115,24],"target":[-25,-35]},
                     {"id":"core","pos":[-110,16],"target":[-163,-148]}]}
    (OUT/"map.json").write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    sources = json.loads((GEO/"sources.json").read_text(encoding="utf-8"))
    sources.update({"base_height_m":base,"height_range_m":[float(heights.min()+base),float(heights.max()+base)],
                    "raster_m":1,"source_resolution_m":0.5,"fetched":"2026-09-28",
                    "sha256":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(GEO.glob("*.tif"))},
                    "interpretation":"Crop species/season from user photographs; parcel outlines and groves traced from SWISSIMAGE. Buildings use OSM footprints with representative existing facades. Tree heights and widths are estimates."})
    (OUT/"sources.json").write_text(json.dumps(sources,indent=2),encoding="utf-8")
    overview(data)
    print(f"PLANES altitude={base:.2f} range={heights.min()+base:.2f}..{heights.max()+base:.2f}; roads={len(roads)} buildings={len(buildings)} trees={len(trees)}")


def overview(data):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(13,11))
    ax.imshow(Image.open(GEO/"aerial.jpg"),extent=(-650,850,650,-650))
    for field in FIELDS:
        p=np.array(field["poly"]+[field["poly"][0]])
        ax.plot(p[:,0],p[:,1],color="#f5cc60" if field["kind"]=="wheat" else "#a5f276",lw=1.5)
    for view in data["views"]:
        x,z=view["pos"]; tx,tz=view["target"]
        ax.annotate(view["id"],(x,z),(x-140,z+80),color="white",arrowprops={"color":"white"})
    ax.scatter([0],[0],marker="+",s=100,c="red",label="User coordinate")
    ax.set(xlim=(X0,X1),ylim=(Z1,Z0),xlabel="Metres east of pin",ylabel="Metres south of pin",
           title="The Planes / Remetschwil — SWISSIMAGE + photo-authored crop parcels")
    ax.legend(); fig.tight_layout()
    folder=ROOT/"artifacts/planes"; folder.mkdir(parents=True,exist_ok=True)
    fig.savefig(folder/"geodata-overview.png",dpi=140); plt.close(fig)


if __name__=="__main__": main()
