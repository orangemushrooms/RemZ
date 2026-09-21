# Ton-Bestandsaufnahme (21. September 2026)

Vollständige Durchsicht aller `Sfx.play / play_at / event / footstep`-Aufrufe in `godot/scripts/`,
abgeglichen mit `Sfx.FILES`, den Dateien in `assets/audio/` und den prozeduralen Ersatzklängen in
`Sfx._procedural()`.

## Wie der Ton aufgebaut ist

`Sfx.get_stream(name)` sucht in dieser Reihenfolge:

1. **Aufnahme** — `Sfx.FILES[name]` nennt einen Dateistamm, die Datei liegt in `assets/audio/sfx/`.
2. **Benannter Synth** — kein Eintrag, aber `_procedural()` kennt den Namen und baut einen passenden Burst.
3. **Generischer Blip** — nichts passt: ein nichtssagender 0,1-s-Knacks (`_burst(0.1, 0.03, 0.5, 0.3)`).

Dazu kommt eine vierte, unsichtbare Kategorie: **geliehene Klänge**, bei denen ein Ereignis absichtlich
die Aufnahme eines anderen abspielt (Marksman nutzt den Revolver, der Turm die MP5 …). Die klingen
korrekt, aber eben nicht eigenständig.

Zum Nachziehen: Datei nach `assets/audio/sfx/<stamm>.mp3` legen, Stamm in `Sfx.FILES` eintragen,
danach `Godot.exe --headless --path godot --import`.

---

## A · Komplett stumm — höchste Priorität

Hier wird gar kein Ton abgespielt.

| Ereignis | Ort | Bemerkung |
|---|---|---|
| Feuerpatrone Einschlag | `elemental_effects.gd` | Die ganze Datei hat **null** Audio |
| Frostpatrone Einschlag | `elemental_effects.gd` | dito |
| Brennender Zombie (Schleife) | `zombie.gd` Status | Flammen sind nur sichtbar |
| Vereister Zombie (Knirschen) | `zombie.gd` Status | Eisüberzug ist nur sichtbar |
| Zombie holt aus / schlägt zu | `zombie.gd` | Nur der Spieler stöhnt beim Treffer |
| Mara begrüsst dich | `progression.gd` `VOCALS` | **4 Aufnahmen liegen bereit, nicht verdrahtet** (siehe F) |
| Waffen-Mod anbauen / abnehmen | `weapon_mods.gd` | stumm |
| Skin wechseln | `weapon_skins.gd` | stumm |
| Zielen an / aus, Zielfernrohr | `scope_overlay.gd`, `weapons.gd` | stumm |
| Springen und Vault über ein Tor | `player.gd` | nur die Landung hat Ton |
| Ducken / Aufstehen | `player.gd` | stumm |
| Turm besteigen / verlassen | `defence_system.gd` | stumm |
| Punkte abwerfen (Taste für Bargeld) | `pickup.gd` `throw_cash` | Aufheben hat Ton, Werfen nicht |
| Intro-Schreibmaschine | `intro.gd` | nur Musik |
| Spielende / neuer Bestwert | `main.gd` `_game_over` | nur Musikwechsel, kein Stinger |
| Tag-/Nachtwechsel | `day_night_cycle.gd` | stumm |

---

## B · Nur geliehen — klingt nach etwas anderem

| Ereignis | Spielt aktuell | Eigener Ton wäre |
|---|---|---|
| Waldläufer .308 (marksman) | `revolver` | schwerer Repetierer mit Hall |
| MG-60 (lmg) | `ak47`, Tonhöhe 0,88 | tieferes, langsameres MG |
| Nachtbrecher 12 (breacher) | `shotgun` | kurze, harte Kampfflinte |
| Titanenbrecher .50 (titanbreaker) | `revolver`, Tonhöhe 0,72 | Anti-Materiel-Knall |
| Waldaxt | `melee` (gleich wie Gewehrkolben) | schwerer Axthieb |
| Turm „standard" und „mg42" | `smg` | **Aufnahmen liegen bereit** (siehe F) |
| Mörserturm | `shotgun` | **Aufnahme liegt bereit** (siehe F) |
| Mörsergranate Einschlag | `boom` (gleich wie Handgranate) | dumpferer, grösserer Einschlag |
| Kaufen / Waffe aufheben / Loot | alle drei `gun_pick_up.mp3` | Kauf = Münzen, Loot = Stoff/Metall |
| Munitions-, Medikit-, Granaten-Drop | alle `pickup` | drei unterscheidbare Klänge |
| Hütten-Alarm | `wave_start`, Tonhöhe 0,7 | eigene Alarmglocke |
| Welle überstanden | `menu` (UI-Klick!) | Entwarnung / Fanfare |
| Reh flieht | `rustle` | Hufe plus Blätter |
| Nebelkrämer (wanderer) | `secret_vendor_vocal` | eigene Stimme |
| Zombie-Typen runner/brute/nurse/soldier | alle `zombie_1…4` | je Typ eine eigene Kehle |
| Mitspieler-Schritte im Coop | immer `step_leaves` | Untergrund wie beim eigenen Spieler |
| Barrikade reparieren | `build` (gleich wie Bauen) | Hämmern statt Aufbauen |

---

## C · Zur Laufzeit synthetisiert

Funktioniert, ist aber synthetisch und hört sich auch so an.

- `hurt_thud` — der dumpfe Aufprall zusätzlich zum Schmerzlaut
- `tower_flame` — Flammenwerferturm
- `tower_tesla` — Teslaturm
- **Schritt-Texturschicht** je Untergrund (Gras, Laub, Kies, Holz, Mais) — liegt über den drei
  aufgenommenen Stiefeltritten
- **Maisrauschen** beim Durchlaufen (`Sfx.corn_bed`)
- **Gesamte Umgebung** (`ambience.gd`): Wind, Blätterrauschen, Lagerfeuer, Bach, Vogelgezwitscher

## D · Vorgebacken per Skript — echte Dateien, aber keine Aufnahmen

- `assets/audio/sfx/titan/` · 8 WAV (roar 1–3, windup, slam, step 1–2, death), erzeugt von
  `tools/build_titan_audio.py` aus deinen Zombie-Aufnahmen. `collapse` benutzt `slam` mit.
- `assets/audio/fireworks/` · 10 Dateien (burst 1–4, cracker 1–4, crackle, fuse), erzeugt von
  `tools/build_firework_audio.py`. Nur `launch.mp3` ist eine echte Datei.

## E · CC0-Fremdmaterial — echte Aufnahmen, aber nicht deine

Eingespielt am 20. September, Quellen in `sfx/SOURCES_CC0.md`. Klingt brauchbar; ersetzen lohnt nur,
wo es dir auffällt.

`melee_*`, `melee_stab_*`, `wood_hit_*`, `build_*`, `grenade_bounce_*`, `weapon_switch_*`,
`flashlight`, `hover_*`, `door_close_*`, `door_locked`, `zombie_death_*`, `hurt_*`, `player_death_*`,
`consume_*`, `crash`, `pumpkin_splat`, `boom`, `grenade_throw`, `achievement`, `streak`, `rustle`,
`mushroom_pickup`, `hut_collapse`, `heartbeat`, `land`

## F · Liegt bereit, ist aber nicht verdrahtet

Diese Dateien sind schon im Projekt und werden von keinem Code geladen:

- `Machinegun_Tower.mp3`, `Mortar_Tower.mp3`, `Teslacoil_Tower.mp3`, `flamethrower_tower.mp3`
- `mara_sfx_hello.mp3`, `mara_sfx_good_morning.mp3`, `mara_sfx_good_evening.mp3`,
  `mara_sfx_good_night.mp3`

Die Mara-Dateien sind nach Tageszeit benannt — dafür braucht es eine kleine Erweiterung, weil
`Progression.VOCALS` bisher nur einen Klang je NPC kennt.

## G · Deine eigenen Aufnahmen — in Ordnung

Pistole, Revolver, MP5, AK-47, Schrotflinte, Nachladen, leeres Magazin, Messerhieb, drei Stiefeltritte,
Wellenstart, Tür auf, Treffer-Impact, vier Zombiekehlen, vier Eulen, drei Raben, Schlüsselfund,
Auftrag angenommen (2), Auftrag erledigt, Vendor (3), Secret Vendor, Mechanic (3), UI-Klick und
-Bestätigung.

---

## Wenn du Dateien lieferst

MP3 oder OGG, mono für Positionsklänge, 44,1 kHz. Mehrere Varianten gern als `name_1`, `name_2`, …
— die werden automatisch abwechselnd gespielt, ohne zweimal hintereinander dieselbe. Dateien einfach
nach `godot/assets/audio/sfx/` legen und mir die Namen sagen, den Rest verdrahte ich.
