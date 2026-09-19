# Feldtitan

Originales generiertes Spielmodell, erstellt am 19.09.2026 über die vorhandene Meshy-Pipeline. Prompt: `tools/assets.json`, Eintrag `zombie_titan`. Keine übernommenen Dark-Souls-Modelle.

- Meshy 6, Ziel 28.000 Dreiecke, Texturen 2K, humanoides Rig bei 1,7 m Referenzhöhe.
- Im Spiel auf 27 m skaliert; Animationen `walk`, `attack`, `death` aus Meshy-Aktionen 112, 214, 184.
- Normale und Metall-/Rauheitskarten aus dem verfeinerten Modell werden nach dem Rigging wieder eingesetzt. `tools/finish_titan.mjs` prüft zuvor den unveränderten UV-Atlas (34.467 / 34.467 passende UV-Koordinaten).
- Lauf reproduzieren: `python tools/gen_asset.py zombie_titan --rig --pose t-pose --pbr --polycount 28000 --anim 112:walk --anim 214:attack --anim 184:death`, dann `node tools/pack.mjs zombie_titan --size 2048`, `node tools/finish_titan.mjs`, Godot-Import.
- Rohdateien und wiederaufnehmbare Task-IDs: `assets/raw/zombie_titan/`.
