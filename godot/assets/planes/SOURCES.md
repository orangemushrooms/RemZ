# The Planes source data

- User reference: 47.404384449011665, 8.335047115511859, five supplied location/map images.
- Terrain: [swissALTI3D](https://www.swisstopo.admin.ch/de/hoehenmodell-swissalti3d), © swisstopo, 2021 tiles; open government geodata. Fine source 0.5 m, local output 1 m. Surroundings source 2 m, output 10 m.
- Roads and building footprints: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL, retrieved 2026-09-28.
- Parcel/grove tracing reference: [SWISSIMAGE](https://www.swisstopo.admin.ch/de/orthobilder-swissimage-10), © swisstopo, WMS current orthophoto retrieved 2026-09-28.

Exact downloaded terrain URLs and checksums: `sources.json`. Rebuild with `tools/planes_geo.py` then `tools/build_planes.py`.

Crop types, widths of untagged roads, crown sizes and facade details are photo-based interpretations. No Google imagery is redistributed as a game texture. Existing project models and textures retain their original provenance. See `docs/THE_PLANES.md` for model reuse and accuracy limits.
