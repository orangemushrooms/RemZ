# Birkenhof Nacht (RemZ)

> Das aktuelle Spiel ist die Godot-Version **RemZ – Remetschwil Sennhof**. Start, Steuerung, Grafikoptionen und Tests stehen in [godot/README.md](godot/README.md). Ein Windows-Export liegt lokal in `builds/windows/RemZ.exe` (zusammen mit `RemZ.pck` verwenden). Die Browser-Anleitung unten beschreibt den älteren Prototyp.

First-Person Zombie-Survival im Browser (Three.js + Vite). Die Karte ist der Weg "Birkenhof" aus den
Street-View-Fotos: Asphaltweg bergauf, links offenes Feld mit Blick ins Tal, rechts Waldrand mit Hecke,
oben ein Kies-Wendeplatz mit drei grünen Bänken. Der Wendeplatz ist der Verteidigungspunkt.

## Spielen

```bash
npm install
npx vite
```

Dann http://localhost:5173 öffnen. Steuerung: WASD, Shift sprinten, Maus zielen und schiessen, R nachladen,
1/2 Waffe, E Barrikade bauen oder reparieren, F Taschenlampe.

## Assets (Meshy)

Alle 3D-Modelle kommen aus der Meshy-API. Der Key liegt in `.env` als `MESHY_API_KEY` (nicht einchecken).

```bash
# Windows: UTF-8 erzwingen, sonst bricht die Fortschrittsanzeige ab
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
python tools/gen_asset.py tree_pine --polycount 3000
python tools/gen_asset.py zombie_shambler --rig --pose t-pose --anim 112:walk --anim 214:attack --anim 184:death
node tools/pack.mjs tree_pine zombie_shambler      # oder: node tools/pack.mjs --all
```

- Prompts stehen in `tools/assets.json`. Rohdaten landen in `assets/raw/<name>/`, der Lauf ist über `state.json` wiederaufnehmbar.
- `tools/pack.mjs` führt die Animationsclips zusammen, verkleinert Texturen auf 1024 px WebP und schreibt `public/models/<name>.glb` plus `<name>.glb.json` (Base64, weil das Artifact-Hosting nur Standard-Webtypen ausliefert).
- Ein Modell austauschen: neue Datei mit gleichem Namen nach `public/models/`, Skalierung und Clipnamen stehen im Manifest in `src/assets.js`. Fehlt eine Datei, nimmt das Spiel einen Platzhalter aus Primitiven.
- Eigene Fototexturen: `public/textures/grass.jpg`, `asphalt.jpg`, `gravel.jpg` überschreiben die prozeduralen Texturen.

## Veröffentlichen als Artifact

```bash
npx vite build
node tools/publish-prep.mjs
```

Danach `dist/artifact.html` zusammen mit den Dateien aus `dist/files.json` veröffentlichen.

## Code

- `src/world.js` Karte, Gelände, Vegetation, Licht, Kollisionen (`MAP` enthält Barrikaden-Slots und Spawnpunkte)
- `src/player.js` Bewegung, Mausblick (Pointer Lock mit Fallback), Taschenlampe
- `src/weapons.js` Pistole und Schrotflinte, Raycast-Treffer, Rückstoss
- `src/zombies.js` Zombietypen, KI, Animationen, Blutpartikel
- `src/barricades.js` Bauen, Reparieren, Blockieren
- `src/waves.js` Wellenplanung
- `src/audio.js` Sounds per WebAudio, keine Dateien
- `window.remz.step(dt, n)` treibt die Simulation ohne requestAnimationFrame voran (für Tests)


## Umzug auf einen anderen PC

1. Repo klonen (Code, Meshy-Modelle, Texturen, Sprites sind drin).
2. Godot 4.7.2 (Windows, 64 Bit, Standard-Version ohne .NET) von godotengine.org laden, keine Installation nötig.
3. Grosse Baummodelle sind nicht im Repo: entweder den Ordner `godot/assets/trees` (ca. 1 GB) vom alten PC kopieren,
   oder neu erzeugen: Python 3.13 mit `pip install requests pillow numpy`, Blender 5.x, dann
   `python tools/fetch_polyhaven.py`, `python tools/autumn_leaves.py`,
   `"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P tools/tree_reduce.py`.
4. Projekt in Godot öffnen, der erste Import dauert wegen der Bäume einige Minuten.
5. Nur wenn weitere Meshy-Modelle erzeugt werden sollen: `.env` mit `MESHY_API_KEY` anlegen, Node.js installieren
   und `npm install` im Repo ausführen.
