# The Planes source data

- User reference: 47.404384449011665, 8.335047115511859, five supplied location/map images.
- Terrain: [swissALTI3D](https://www.swisstopo.admin.ch/de/hoehenmodell-swissalti3d), © swisstopo, 2021 tiles; open government geodata. Fine source 0.5 m, local output 1 m. Surroundings source 2 m, output 10 m.
- Roads and building footprints: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL, retrieved 2026-09-28.
- Parcel/grove tracing reference: [SWISSIMAGE](https://www.swisstopo.admin.ch/de/orthobilder-swissimage-10), © swisstopo, WMS current orthophoto retrieved 2026-09-28.

Exact downloaded terrain URLs and checksums: `sources.json`. Rebuild with `tools/planes_geo.py` then `tools/build_planes.py`.

Crop types, widths of untagged roads, crown sizes and facade details are photo-based interpretations. No Google imagery is redistributed as a game texture. Existing project models and textures retain their original provenance. See `docs/THE_PLANES.md` for model reuse and accuracy limits.

`branches_near.glb` and `branches_far.glb` are geometry reductions of the existing Meshy `assets/models/tree_birch.glb` (3,486 / 663 triangles), produced by `node tools/planes_branch_lods.mjs`. They retain its shape and use the project's existing bark texture; runtime foliage reuses `assets/sprites/leaf_beech.png`. No new external model or image was commissioned for this revision.

Target stand correction: the user identified OSM way 1558294553 as the targets of the shooting house below, not housing. Its source tags are `building=yes`, `layer=-1`. The [SG Remetschwil facility description](https://sgremetschwil.ch/startseite/ueber-den-verein/schiessanlage-anfahrt/) confirms a 300 m range with six targets; its site photos informed the low concrete stand. The targets face the surveyed shooting-house footprint, way 118083383. The 2.3 m visual/collision envelope and small construction details are approximations, not measured dimensions. Reference photos are not redistributed as textures.
