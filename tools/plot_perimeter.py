"""Overlay of the palisade ring (perimeter.gd) on the map data: roads, huts, clearing, trees, gates and the
ring polygon over a shaded heightmap, plus slope statistics per ring edge. Output tools/out/perimeter_check.png.
Usage: python tools/plot_perimeter.py
The ring vertices below must match Perimeter.CORNERS in godot/scripts/perimeter.gd.
"""
import os, json, math, struct
import numpy as np
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, "godot", "assets", "map")
OUT = os.path.join(ROOT, "tools", "out")
X0, X1, Z0, Z1 = -60, 70, -60, 90
PPM = 6

# ring corners between the gates, clockwise seen from above (x east, z south); the gate entries are
# ["gate", id, side] where side "a" = centre + dir * half_len, "b" = centre - dir * half_len
RING = [
    ["gate", "w", "a"], [-2, -37], [12, -34], [24, -22], [32, -6], [36, 12], [38, 30], [39, 42],
    ["gate", "ne", "b"], ["gate", "ne", "a"], [22, 64],
    ["gate", "e", "a"], ["gate", "e", "b"], [-6, 69],
    ["gate", "s", "a"], ["gate", "s", "b"], [-26, 56], [-30, 40], [-30, 20], [-31, 0], [-30, -18],
    ["gate", "w", "b"],
]

def main():
    m = json.load(open(os.path.join(MAP, "map.json"), encoding="utf-8"))
    w, h = m["w"], m["h"]
    hm = np.frombuffer(open(os.path.join(MAP, "heightmap.f32"), "rb").read(), dtype="<f4").reshape(h, w)
    def height(x, z):
        i = int(round(z - m["z0"])); j = int(round(x - m["x0"]))
        return float(hm[min(max(i, 0), h - 1), min(max(j, 0), w - 1)])
    gates = {g["id"]: g for g in m["barricades"]}
    def gate_end(gid, side):
        g = gates[gid]; yaw = g["yaw"]; half = g["segments"] * 3.2 * 0.5
        d = (math.cos(yaw), -math.sin(yaw))
        s = 1 if side == "a" else -1
        return (g["pos"][0] + d[0] * half * s, g["pos"][1] + d[1] * half * s)
    pts = []
    for e in RING:
        pts.append(gate_end(e[1], e[2]) if e[0] == "gate" else (float(e[0]), float(e[1])))
    W, H = (X1 - X0) * PPM, (Z1 - Z0) * PPM
    def px(p): return ((p[0] - X0) * PPM, (p[1] - Z0) * PPM)
    # shaded relief background
    sub = hm[int(Z0 - m["z0"]):int(Z1 - m["z0"]), int(X0 - m["x0"]):int(X1 - m["x0"])]
    gy, gx = np.gradient(sub)
    shade = np.clip(0.6 + 0.4 * (-gx * 3 + gy * 2), 0.2, 1.0)
    img = Image.fromarray((shade * 200).astype(np.uint8), "L").resize((W, H), Image.BILINEAR).convert("RGB")
    d = ImageDraw.Draw(img)
    for r in m["roads"]:
        d.line([px(p) for p in r["pts"]], fill=(210, 190, 120), width=max(2, int(r["width"] * PPM)))
    d.polygon([px(p) for p in m["clearing"]], outline=(120, 200, 120))
    for name, b in m["buildings"].items():
        cx, cz = b["pos"]; sx, sz = b["size"]
        d.rectangle([px((cx - sx / 2, cz - sz / 2)), px((cx + sx / 2, cz + sz / 2))], outline=(255, 80, 80), width=2)
    for t in m["trees"]:
        if X0 < t[0] < X1 and Z0 < t[1] < Z1:
            p = px((t[0], t[1])); d.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(40, 110, 40))
    for key in ["fire", "bin", "signpost"]:
        p = px(m[key][:2]); d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(255, 140, 0))
    # ring
    d.line([px(p) for p in pts] + [px(pts[0])], fill=(255, 255, 255), width=3)
    total = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        ea = RING[i]; eb = RING[(i + 1) % len(RING)]
        is_gate = ea[0] == "gate" and eb[0] == "gate" and ea[1] == eb[1]
        L = math.dist(a, b)
        n = max(2, int(L))
        hs = [height(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1)]
        slope = max(abs(hs[k + 1] - hs[k]) for k in range(n)) / (L / n)
        if is_gate:
            d.line([px(a), px(b)], fill=(255, 60, 60), width=5)
        else:
            total += L
        print("%-5s %7.1f,%6.1f -> %7.1f,%6.1f  len %5.1f m  dh %5.1f m  max slope %4.0f %%" % (
            "GATE" if is_gate else "wall", a[0], a[1], b[0], b[1], L, hs[-1] - hs[0], slope * 100))
    for gid, g in gates.items():
        p = px(g["pos"]); d.text((p[0] + 6, p[1] - 6), gid + " " + g["name"], fill=(255, 255, 0))
    print("wall length %.0f m" % total)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "perimeter_check.png"))
    print("saved tools/out/perimeter_check.png")

if __name__ == "__main__":
    main()
