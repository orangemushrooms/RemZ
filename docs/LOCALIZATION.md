# Localization (English default, German optional)

RemZ is written in **English**. German is a translation the player can pick under
Settings > Language (saved as `[game] language` in `user://settings.cfg`). Without a saved choice the
game starts in English, whatever the Windows locale says. Tests always run in English unless they pass
`--lang=de`.

## Pieces

| File | Role |
|---|---|
| `godot/scripts/lang.gd` | `class_name Lang`, autoload `Language`. Installs one `Lang.Catalogue` (a `Translation`) per language into the `TranslationServer`, picks the language at startup, `Lang.t()`, `Lang.text()`, `Lang.raw()`, `Lang.set_language()`. |
| `godot/locale/de.po` | The German catalogue: `msgid` = English text exactly as in the code, `msgstr` = German. Generated order, edit through the tool. |
| `tools/i18n.py` | `merge` fragments into de.po, `check` (CI-style gate), `review` (English literals without a German entry), `write` (re-sort). |
| `tools/i18n_allow.txt` | Literals the checker must not flag (place names, brand names, debug text that is not player-facing). |
| `godot/tests/language.gd` | `--suite=language`: default English, saved choice, live switching, portable co-op text, a German sweep over every menu. |

## How text reaches the screen

1. **Static text: a plain English literal.** `label.text = "Start game"`, `_label("Health", 14)`,
   `button.tooltip_text = "..."`, `option.add_item("Unlimited")`, `hud.message("No repair needed.")`,
   a `Label3D.text`. Godot's auto-translate shows the German msgstr when German is active and switches
   live when the player changes the language. The property keeps the English source, so logic and
   tests that read `.text` see English.
2. **Text built from pieces: `Lang.t(msgid, args)`.** `Lang.t("Wave %d", [n])`,
   `Lang.t("Bought: %s · magazine + 2 spare magazines", [def.name])`. It returns a *portable segment*
   (the msgid framed by the Unicode noncharacters U+FDD0..U+FDD2, arguments as base64) that is
   translated where it is shown, in that machine's language. That is what makes co-op work: the host
   builds a message for a client, the client reads it in its own language. Segments can be concatenated
   (`"[b]" + Lang.t("Quests") + "[/b]"`) and nested as arguments, but plain text glued next to a segment
   is **not** translated, so every translatable piece of a composed label must be a segment. **String
   arguments are translated too** (pass `def.name`, not a resolved text); numbers stay numbers.
   `Lang.raw(name)` passes a player name or typed input through untouched.
3. **Places Godot does not translate: `Lang.text(value)`.** `draw_string`, `Font.draw_string` on a
   RenderingServer canvas item, `get_string_size` measurements, `RichTextLabel.append_text/add_text`,
   window titles, and code that must look at the final wording. Custom-drawn nodes redraw on
   `NOTIFICATION_TRANSLATION_CHANGED`.

`tr()` is **not** used: its result is frozen in one language, would not follow a live switch and would
send the host's language to co-op clients.

Rules that keep this working:

- Never compare displayed text for logic. Compare ids, or the English source a static `.text` holds.
- Keys, ids, node names, groups, input actions, sound ids, JSON/network keys and developer logs are
  not translated. German log lines may be rewritten in plain English without `Lang`.
- A literal `%` in a msgid that is formatted with arguments is `%%`. English writes `30%`, German `30 %`.
- `msgid`s are whole sentences with placeholders, not fragments glued together, so German can keep its
  word order. Keep the argument order of the original German text.
- A label that shows a `Lang.t` segment holds the segment in `.text`; tests compare
  `Lang.text(label.text)`.
- Numbers-only labels (`"%d / %d"`, `"%s R"`) need no translation.
- Label/Button text is shaped by Godot through `TranslationServer.translate()`, so a German msgstr that
  is itself an English msgid with a different meaning would be translated twice. `i18n.py check`
  reports these as `TWICE`.
- Upper-casing or splitting a translated text (`to_upper()`, `split("; ")`) only works on the resolved
  text: `Lang.raw(Lang.text(name).to_upper())`, and only for UI built on this machine.
- The catalogues are script objects inside the `TranslationServer`; `Lang.uninstall()` removes them when
  the scene tree's root exits, before scripting shuts down (freed later, they crashed Godot on exit).

## Adding or changing text

1. Write the English text in the code (rules above).
2. Add the German translation: a JSON fragment `{"English msgid": "German msgstr"}` and
   `python tools/i18n.py merge fragment.json` (Windows: `PYTHONIOENCODING=utf-8 PYTHONUTF8=1`).
3. `python tools/i18n.py check` must report 0 problems. `review` lists English literals that have no
   German entry yet (not all of them are player-facing).
4. `Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=language --smoke-test --no-intro --no-music --no-foliage`

German msgstr use Swiss spelling (`ss`, never `ß`) and real umlauts.

## Glossary

Use these English terms everywhere so the game reads as one voice.

| German | English |
|---|---|
| Welle / Runde | wave / round |
| Einsatzlevel | mission level |
| Stufe (Turm, Barrikade) | tier |
| Waldhütte, Hütte | forest hut, the hut (title: REMETSCHWIL FOREST HUT) |
| Holzlager | woodshed |
| Lagerfeuer / Feuerstelle | campfire / fire pit |
| Palisade(nring) | palisade (ring) |
| Barrikade / Sperre / Sperrlinie / Linie | barricade / barrier / barrier line / line |
| Zugang / Tor / Bauplatz | approach / gate / building site |
| Weg zur Hütte / Wiesentor / Weg Richtung Dorf / Waldweg Nord | Hut Path / Meadow Gate / Village Path / North Forest Path |
| Turm / Geschützturm / Wächter | tower / gun turret / sentinel |
| Turmtypen: Wächter, Flammenwerfer, Mörser, Schweres MG, Teslaspule | Sentinel, Flamethrower, Mortar, Heavy MG, Tesla Coil |
| Verteidigung | defense |
| Händler / Waffenhändler | trader / weapon trader |
| Vendor, Mechanic, Secret Vendor, Mara | unchanged names |
| Nebelkrämer / Krämer | Mist Peddler / the peddler |
| Försterin | forester |
| Auftrag / Aufträge / Questreihe | quest / quests / quest line |
| Belohnung abholen / abgeben / annehmen | collect reward / turn in / accept |
| Kaufberechtigung / Berechtigung | purchase permit / permit |
| Raritäten / Legendär / Talisman | rarities / Legendary / talisman |
| Rem Dollars, R | unchanged |
| Munition / Schuss / Magazin / Reservemagazin / Reserve | ammo / rounds / magazine / spare magazine / reserve |
| Vorrat, Vorräte / Munitionskiste | supplies / ammo crate |
| Granate / Handgranate / Granatentasche | grenade / hand grenade / grenade pouch |
| Verband, Verbandspäckli | bandage, bandage packs |
| Leben, Gesundheit / LP, TP | health / HP |
| Schaden / Rückstoss / Streuung / Reichweite / Nachladen | damage / recoil / spread / range / reload |
| Kopfschuss / Abschüsse / Serie / Treffer / Treffgenauigkeit | headshot / kills / streak / hits / accuracy |
| Läufer / Feldtitan / Titan / Erdwurm | runner / field titan / titan / earthworm |
| Steinpilz / Fliegenpilz / Pfifferling / Morchel | porcini / fly agaric / chanterelle / morel |
| Wildfleisch roh / gegrillt | raw venison / grilled venison |
| Feuerwerk / Batterie / Rakete / Böller | fireworks / battery / rocket / firecracker |
| Schlüssel / Teamschlüssel / Tür | key / team key / door |
| Inventar / Schnellzugriff / Platz | inventory / quick bar / slot |
| Lackierung / Originalfinish | finish / original finish (the tab stays "Skins") |
| Mündung / Magazin / Verschluss / Lauf (Mod-Plätze) | Muzzle / Magazine / Bolt / Barrel |
| Training / Ausbauten | training / upgrades |
| Bestenliste / Leaderboard / Erfolge / Bilanz | high scores / leaderboard / achievements / summary |
| Koop, Mehrspieler / Mitspieler / Sitzung | co-op, multiplayer / teammate / session |
| wiederbeleben / am Boden, ausgeschieden | revive / down |
| Morgen / Tag / Abend / Nacht / Ortszeit / Spielzeit | Morning / Day / Evening / Night / local time / play time |
| Leicht / Normal / Schwer / Albtraum | Easy / Normal / Hard / Nightmare |
| Strg / Leertaste / Linksklick / Rechtsklick / Mausrad | Ctrl / Space / Left click / Right click / Mouse wheel |
| Sennhofstrasse, Heitersberg, Remetschwil, Oberrohrdorf, Sennhof, Oberer Sorchen | unchanged place names |

Style: American spelling (color, defense, armor), sentence case for buttons ("Start game"),
ALL CAPS where the German used ALL CAPS, keep ` · `, `…`, `×`, `−` as they are, address the player
as "you".
