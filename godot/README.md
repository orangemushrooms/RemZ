# RemZ – Remetschwil Sennhof

Das aktuelle Spiel ist das Godot-Projekt in diesem Ordner. Der Three.js-Code im übergeordneten `src/` ist der ältere Browser-Prototyp.

## Starten

`project.godot` mit Godot 4.7.2 öffnen und F6/F5 drücken. Der Startknopf wird freigegeben, sobald das begehbare Wegnetz fertig ist.

Der Windows-Export liegt unter `../builds/windows/RemZ.exe`. Zum Weitergeben den gesamten Ordner `windows` verwenden: Die EXE benötigt die benachbarte `RemZ.pck`.

## Steuerung

**Pilze im ganzen Wald:** Die zehn gewöhnlichen Sorten wachsen über die gesamte spielbare Waldfläche verteilt, auch weit abseits der Hütte und im tiefen Wald. Pro 18-Meter-Bereich werden bis zu zwei geeignete Fundstellen gewählt; Wege, Lichtungen, Gebäude, Wasser, Baumstämme und steile Hänge bleiben frei. Die Verteilung ist im Koop identisch und die Pilze bleiben einzeln einsammelbar.

**Waldaxt:** Linksklick oder H: leichter Schlag (125 Schaden, 0,95 s). Rechtsklick: schwerer Hieb (225 Schaden, 1,45 s, 5,0 m Reichweite, engerer Trefferbereich). Gemeinsame Angriffssperre, getrennte Animationen und Koop-Synchronisierung. Das neue Modell besitzt einen ovalen, geschwungenen Holzstiel mit Maserung, einen verjüngten geschmiedeten Kopf und eine geschliffene Schneide.

**Feldmesser:** Linksklick (oder H) schneidet schnell: 55 Schaden, 0,42 s Erholung. Rechtsklick sticht gezielt: 110 Schaden, 4,4 m Reichweite, 0,85 s Erholung und schmalerer Trefferbereich. Beide teilen dieselbe Angriffssperre; Stich und Schnitt besitzen eigene Animationen und werden im Koop unterschieden.

**Maisfeld am westlichen Waldrand:** Auf dem Feldhang Richtung Dorf, mit der langen Seite parallel zum schrägen oberen Waldrand. Feld, Labyrinthwände, Verstecke und Vogelscheuchen verwenden dieselbe gedrehte Ausrichtung; die Ostseite Richtung Sennhof bleibt Wiese. Der Dorfweg bleibt ausserhalb des Feldes. Mais wird nur auf Wiesengrund mit mindestens sechs Metern Abstand zu Bäumen gepflanzt. Die Pflanzen besitzen gebogene Blätter mit Mittelrippen, umhüllte Kolben und feine Rispen. Eigene Mais-, Vogelscheuchen-, Raben- und Eulenmeshes liegen unter `assets/cornfield/`; `tests/build_corn_meshes.gd` erzeugt sie reproduzierbar. Der Mais wiegt sich im Wind und wird in räumlichen MultiMesh-Gruppen gerendert. Das Labyrinth besitzt zwei verbundene Ausgänge und fünf einmalig plünderbare Verstecke: Feuerpatronen, Frostpatronen, 250 Punkte, eine Granate und Munition. Mit **E** aufnehmen; bei vollem Vorrat bleibt die Kiste liegen. Im Koop sind die Kisten gemeinsam und werden vom Host verwaltet. Straßen und Titanen-Zugänge bleiben frei. Raben fliegen bei Annäherung oder Schüssen auf und landen später wieder; Eulen kreisen zwischen 20 und 5 Uhr. Beide haben eigene räumliche Rufe. Die Vögel sind lokale, rein dekorative Tiere und benötigen keine laufenden Netzwerkpakete.

**Mehrspieler:** Im Hauptmenü unter **Mehrspieler / Hamachi** ein Spiel erstellen oder mit der Hamachi-IP des Hosts beitreten. Bis zu vier Spieler, Standardport UDP 24567. Der Host startet die gemeinsame Runde. Mit **E** einen Mitspieler wiederbeleben; Menüs pausieren den Koop nicht. Einrichtung und Spielregeln: [Multiplayer-Anleitung](../docs/MULTIPLAYER.md).

| Eingabe | Aktion |
| --- | --- |
| WASD / Maus | Bewegen / umsehen |
| Shift | Sprinten |
| Strg + Shift + D | Cheatmenü: Wellen überspringen, geheimen Händler oder Wanderhändler auf der Karte anzeigen. Der violette Wanderhändler-Marker folgt seiner Position ab Welle 5, auch auf der großen Karte (M). |
| Strg halten | Ducken: halbes Gehtempo, 30 % weniger Streuung, niedrigere Kamera und Kollision. Kein Sprint/Sprung; Aufstehen nur bei freier Kopffreiheit. |
| Linke / rechte Maustaste | Schießen / zielen |
| R | Nachladen |
| 1–9 / 0 | Schnellzugriff: Plätze 1–10 verwenden (0 = Platz 10) |
| Mausrad | Nächste verfügbare Waffe wählen |
| G | Granate |
| H | Mit Messer/Axt zuschlagen; mit Schusswaffen Kolbenschlag, auch beim Nachladen |
| Enter | Wartezeit überspringen, nächste Welle sofort starten |
| E | NPC ansprechen / Barrikade bauen oder reparieren / Turm besteigen oder verlassen / Gegenstand oder Tür |
| V | Verteidigungsberatung bei Mechanic |
| T | Turmbaumenü mit fünf Typen; R/Mausrad dreht die Vorschau, E baut, T/Escape bricht ab |
| I | Inventar |
| B | Bis zu 100 Punkte abwerfen |
| F | Am Turm reparieren, sonst Taschenlampe |
| Q | Auftragsanzeige ein-/ausblenden |
| Tab halten | Leaderboard: Kills, Headshots, Deaths, Titan Kills, Assists, Punkte, Ping |
| Escape | Pause / fortsetzen |
| F11 | Vollbild umschalten |

Die drei Kürbisse am Lager lassen sich mit Schusswaffen zerstören. Der erste zerschossene Kürbis schaltet den Erfolg **Kürbisknacker** frei (+25 Punkte, einmal pro Runde). Kürbislaternen erlöschen dabei; zerstörte Kürbisse bleiben auch für später beitretende Mitspieler zerstört.

**Erfolge:** 54 Ziele mit dauerhaft gespeicherten Freischaltungen und Belohnungen einmal pro Runde. Der Fortschritt zählt innerhalb einer Runde, im Koop gemeinsam als Team. Neue späte Ziele reichen bis 2500 Zombie-Abschüsse, 500 Kopfschüsse und Welle 40. **Titankiller**, **Titanenjäger**, **Gigantenbezwinger** und **Ende der Titanen** belohnen 1, 5, 15 und 30 besiegte Titanen; alle vier Titanenarten zählen. Weitere Ziele gelten für automatische und selbst bediente Türme, Nahkampf, Abschussserien, schadensfreie Wellen, Jagd, Pilze und Vorräte. Im Erfolgsmenü steht bei jedem Ziel der Fortschritt der aktuellen Runde. Neue Belohnungen vergeben Punkte und gelegentlich Granaten oder Pistolenreserve, ohne zusätzliche maximale Lebenspunkte zu stapeln.

**Spielablauf.** Vor dem Start wählt man im Hauptmenü einen von vier Schwierigkeitsgraden (Leicht, Normal, Schwer, Albtraum: Lebenspunkte, Schaden, Wellengrösse, Tempo, Vorräte, Regeneration und Punktefaktor der Zombies). Die Wellen sind gross: Grundmenge 10 + 5 n Zombies mal Schwierigkeitsfaktor (Welle 1 auf Normal 15, ab Welle 8 mit Armeefaktor bis 4, auf Albtraum das Anderthalbfache), bis zu 72 gleichzeitig, Läufer schon ab Welle 1, Brocken ab Welle 3. Jede fünfte Welle ist eine Bosswelle mit zusätzlichen Brocken. Jeder Zombie erhält zufällig eine von mehreren Meshy-Hüllen: Schlurfer als Bauer, Wanderer, Grossmutter oder klassischer Zombie, Läufer auch als Jogger, Soldaten auch als Forstwart in Warnweste, Titanen als Henker oder ausgemergelter Koloss. Gefallene Zombies lassen Munition für die aktuelle Waffe, Granaten oder Verbandspäckli fallen, die man durch Hindurchlaufen aufnimmt. Abschüsse in schneller Folge (4 s) bauen eine Serie auf, ab dem dritten gibt jeder weitere 10 % mehr Punkte (maximal +100 %); Kopfschüsse zählen das 1,5-Fache. Punkte erscheinen als Einblendung neben dem Fadenkreuz, Treffer auf den Spieler zeigen einen roten Richtungsbogen. Unter 35 % Leben pulsiert eine rote Vignette und der Herzschlag wird hörbar. Schritte klingen je nach Untergrund: Auf Asphalt und Beton laufen die drei Aufnahmen footstep1.mp3 bis footstep3 roh, auf Kies leicht gedämpft mit feinem Knirschen, auf der Wiese dumpfer mit Gras-Rascheln, auf Waldboden am dumpfsten mit Laub-Knistern, im Obergeschoss der Hütte mit hohlem Holzklang (je ein Tiefpass-Bus plus eine prozedurale Texturschicht, `Sfx.footstep`). Gegner werden auf jede Distanz getroffen; ab der Nennreichweite der Waffe fällt der Schaden sanft bis auf 55 % ab.mp3 mit zufälligem Wechsel ohne direkte Wiederholung. Beim Sprinten folgen sie schneller und lauter; Landungen klingen tiefer. Nach dem Tod zeigt die Bilanz Abschüsse, Kopfschüsse, Treffgenauigkeit, beste Serie, Granaten, Barrikaden und Spielzeit; die zehn besten Runden landen dauerhaft in der Bestenliste (`user://highscores.json`). Das Menü (Start, Pause, Spielende) hat Reiter für Briefing, Schwierigkeit, Steuerung, Einstellungen, Bestenliste und Erfolge; aus der Pause führt ein Knopf zurück ins Hauptmenü.

Beide Hände folgen der jeweiligen Waffe beim Zielen, Rückstoß und Nachladen. Die Minimap unten rechts bildet die tatsächlichen Kartendaten ab. Norden bleibt auf der Karte oben; der Spielerpfeil und die Windrose reagieren auf die Blickrichtung. Rote Punkte zeigen Gegner. Sperrlinien sind rot (ungebaut), grün (gebaut) oder gelb (stark beschädigt).

**E an einer Barrikade** baut die ganze Linie für 50 Punkte, verstärkt eine intakte Linie oder repariert eine beschädigte für 25 Punkte. Jede Stufe bringt 300 Strukturpunkte, bis zu 900. Material und Kollision folgen dem Gelände. Bauaktionen sind bis 6 m Abstand möglich; belegte Flächen verhindern den Neubau ohne Punkteabzug. Beratung und Turmausbau gibt es bei Mechanic.

**Händler und Aufträge:** Vendor verkauft Waffen am Lagerfeuer, Mechanic bietet Training und Verteidigung, ein versteckter Händler im Wald führt seltene Waffen. Fünf Aufträge, neun Waffen und drei Lackierungen sind an verdiente Punkte und erreichte Ziele gebunden. Handel findet ausschliesslich beim NPC statt. Steuerung, Preise und Spielregeln: [Fortschritt und Händler](../docs/FORTSCHRITT.md).

Die Hände verwenden modellierte Handschuhe mit Fingerskelett und Normalmaps. Die Ärmel stammen aus einer Meshy-Generierung mit 4K-PBR-Materialien und werden an die Griffpositionen jeder Waffe angepasst. Waffen und Arme werden separat in voller Fensterauflösung mit Kantenglättung gerendert, unabhängig von der 3D-Skalierung der Karte. Quellen und Lizenzhinweise: `assets/viewmodel/SOURCES.md` und `assets/viewmodel/VALVE-LICENSE.txt`.

Jede Waffe hat einen eigenen kurzen Mündungsblitz, Licht auf Händen und Umgebung sowie auslaufenden Pulverdampf. Der Rauch steigt auf und bleibt beim Umsehen in der Welt zurück. Rückstoß hebt die Waffe an, drückt sie zurück und federt gedämpft aus; beim Zielen ist er schwächer. Die Ärmel reagieren mit leichter Stoffbewegung auf Schüsse und Schritte, während die Bündchen an den Händen bleiben. Rauch nutzt einen gemeinsamen Pool mit maximal 48 Instanzen in einem MultiMesh; für die Stoffbewegung werden keine Meshes pro Bild neu aufgebaut. Alle Effekte pausieren mit dem Spiel.

Die Rückstoßabstimmung wurde nach dem Spieltest verstärkt: 60–100 % mehr Grundimpuls nach oben, stärkere Rückwärtsbewegung und langsamere Erholung. Zielen reduziert den Impuls um 25 %; bei Dauerfeuer steigt der Hochschlag weiter an. Der vertikale Kamerawinkel bleibt begrenzt.

## Verteidigung und Titanen

**Titanen-Varianten:** Neben dem 27-m-Feldtitanen gibt es drei kleinere Typen mit vorhandenen Modellen in neuen Größen/Farben, eigenen Bossnamen, Hitboxen und Warnkreisen:

| Typ | Größe | Basis-Leben | Schaden | Warnzeit / Radius | Erste Welle |
| --- | --- | --- | --- | --- | --- |
| Jagdtitan | 8 m | 2400 | 85 | 1,7 s / 4 m | 8 |
| Belagerungstitan | 14 m | 6000 | 130 | 2,8 s / 6 m | 10 |
| Aschetitan | 19 m | 4500 | 100 | 3,2 s / 10 m | 12 |

Der Jagdtitan bewegt sich schnell und schlägt häufiger zu. Der Belagerungstitan ist langsam und zäh; er verursacht 60 % mehr Gebäudeschaden als der Feldtitan. Der Aschetitan deckt eine besonders große Fläche ab, warnt dafür länger. Schwierigkeit, spätere Wellen und Koop skalieren Leben/Schaden wie beim Feldtitanen. Ab Welle 8 kommt pro Welle ein kleinerer Titan hinzu, ab 16 zwei, ab 24 drei; die Varianten wechseln. Die bisherigen Feldtitan-Wellen bleiben bestehen. **Höchstens vier lebende Titanen gleichzeitig**, innerhalb des allgemeinen Gegnerlimits; weitere warten in der Spawnliste. Alle kommen über offene Felder. Varianten zählen für Titanenquests, den Titanenbrecher-Bonus und Frostresistenz und werden mit ihrem eigenen Angriff im Koop synchronisiert. Prüfungen: `titan_variants`, `defence` und `titan_horror`.

**Armeewellen ab Welle 8:** Die reguläre Grundmenge steigt zusätzlich pro Welle um 20 Prozentpunkte: Welle 8 ×1,2, Welle 12 ×2, Welle 17 ×3, ab Welle 22 ×4. Auf Normal solo sind das beispielsweise 60 / 140 / 285 / 480 reguläre Zombies; Brocken-Bossgruppen und Titanen kommen wie bisher dazu. Schwierigkeit und Koop skalieren die Menge zusätzlich. Nach Erreichen von ×4 wächst die Grundmenge weiter mit der Wellennummer. Nachschub kommt bei guter Performance bis alle 0,12 s, höchstens ein neuer Gegner pro Frame. Maximal 72 lebende Gegner sind gleichzeitig aktiv; bei länger erhöhten Frame-Zeiten wird neuer Nachschub auf 56 beziehungsweise 40 aktive Gegner begrenzt und bei starker Last zusätzlich verlangsamt. Lebende Gegner verschwinden dadurch nicht. Alle 0,5 s werden alte Leichen samt Blut-Decals auf maximal 24 begrenzt; Titanen-Leichen haben Vorrang. Die Suche nach sicheren Wald-Spawns ist auf zwölf Kandidaten pro Versuch begrenzt und fällt bei Bedarf auf einen sicheren Zugang zurück. Prüfungen: `army_waves`, `spawn_safety`; optionaler gerenderter Lasttest mit `--army-benchmark`.

**Zielen und Präzision:** Das halbtransparente Fadenkreuz besitzt ein offenes Zentrum und vier feine, gerade Striche. Sein Mittelpunkt folgt der tatsächlichen Schussrichtung, der Abstand der Striche zur Mitte dem berechneten Streubereich. Hüftfeuer ist ungenauer als ruhiges Zielen; Laufen, Sprinten und vertikale Sprungbewegung verschlechtern die Präzision. Schnelle Schussfolgen bauen zusätzliche Streuung und Rückstoß nach oben sowie zu den Seiten auf. Nach einer Feuerpause klingt beides ab. Treffermarkierungen folgen dem verschobenen Fadenkreuz. Beim Nachladen, im Nahkampf und durch das 4×-Zielfernrohr wird das normale Fadenkreuz ausgeblendet; das Zielfernrohr bleibt zur Schussrichtung ausgerichtet, während der Kamerarückstoß das Ziel verzieht. **Mechanic → Training → Ruhige Hand** kostet 180 / 270 / 360 P, reduziert je Stufe die tatsächliche Streuung um 15 % und verbessert die Kontrolle bei Feuerstößen. Präzisionslauf, Kompensator, Schalldämpfer, Falkenauge und Pilze kombinieren sich mit diesen Werten. Der Host berechnet Bewegungseinfluss und Feuerstoß-Streuung selbst. Die Suite `aiming` prüft Käufe, Schussverteilung, Rückstoß, HUD-Projektion, Erholung und identische Berechnung beim Host.

**Nebelkrämer:** Ab dem Beginn von **Welle 5** wandert ein neuer Händler auf begehbaren Routen über die gesamte Karte, einschliesslich Wald, Feldern, Wegen und Lichtungen. Er bevorzugt länger nicht besuchte Kartenteile, auch in den Wellenpausen. Eine violette Laterne und sein Gepäck kennzeichnen ihn. Bei nahen lebenden Spielern bleibt er stehen; **E** öffnet seinen Raritätenhandel. Er bleibt auch nach Sichtkontakt auf Mini- und grosser Karte verborgen; nur der ausdrückliche Karten-Cheat zeigt ihn an. Im Koop bestimmt der Host Position, Käufe und Bestand. Pro neuer Welle gibt es bis zu zwei zufällig gewählte Talismane (je ein Exemplar für das ganze Team), drei Feuerpakete und ab Welle 7 zwei Frostpakete. Höherstufige Talismane können bis zu zwei Level vor ihrer Freischaltung angeboten werden. Ausverkaufte Ware bleibt bis zur nächsten Lieferung gesperrt.

| Rarität | Einsatzlevel | Preis | Wirkung |
| --- | --- | --- | --- |
| Falkenauge | 5 | 1800 P | −35 % Streuung, −20 % Rückstoß |
| Herz der Uralteiche | 8 | 2200 P | −20 % erlittener Schaden |
| Sturmfeder | 9 | 2500 P | −20 % Nachladezeit, +10 % Tempo |
| Blutstein | 10 | 2600 P | Eigene Waffen- und Brandkills heilen 3 Leben; keine Turmkills |
| Phönixasche | 15 | 3800 P | Einmal pro Welle tödlichen Treffer abfangen und 40 % Leben erhalten |
| Drachenatem | 5 | 480 P / 24 Schüsse | 36 Brandschaden über 3 s; Dauer erneuerbar, nicht stapelbar |
| Winterbiss | 7 | 520 P / 18 Schüsse | 3 s Verlangsamung: Zombies −45 %, Titanen −20 % |

Im Inventar **I** lassen sich gekaufte Talismane und Patronensorten kostenlos aktivieren oder ablegen. Es wirkt genau ein Talisman; seine Boni kombinieren sich mit Mods, Training und Pilzen. Wechseln setzt die Phönix-Ladung nicht zurück. Spezialpatronen ergänzen normale Waffenmunition und verbrauchen eine Ladung **pro Schuss**, auch bei Fehlschüssen; Schrot verbraucht eine Ladung für alle Pellets. Maximal 96 Ladungen je Sorte, kein Teilkauf bei voller Tasche. „Normale Patronen“ spart die seltene Munition. Bei Verbrauch der letzten Ladung wird automatisch normale Munition verwendet. Brand- und Frostmarkierungen sowie Partikel zeigen betroffene Gegner; alle Schäden und Verlangsamungen werden vom Host berechnet. Besitz gilt für die laufende Runde. Die Suite `rare_market` prüft Spawn, tatsächliche Wanderung, Handel, Boni, Schüsse, Brandkills und Koop-Zustand.

**Waffen-Mods:** Mechanic und Secret Vendor haben einen eigenen Reiter **Mods**, mit Waffenauswahl und aktuellen Kampfwerten. Pro Waffe gibt es je einen Platz für Mündung, Magazin, Verschluss und Lauf. Käufe gelten für diese Runde und diese Waffe; erneutes Montieren und Entfernen ist kostenlos. Ein anderer Mod im selben Platz ersetzt den bisherigen, der im Besitz bleibt. Auch beim Waffenverkauf bleiben gekaufte Mods für einen späteren Rückkauf erhalten. Munition wird separat bezahlt; größere Magazine vergrößern nicht die Reserve oder die günstigen Munitionspakete. Autorefill füllt die neue Kapazität zum normalen Preis pro Patrone. Beim Verkleinern geht überschüssige Munition in die Reserve; fehlt dort Platz, wird der Wechsel abgelehnt.

| Mod | Händler | Einsatzlevel | Auftrag | Preis |
| --- | --- | --- | --- | --- |
| Schalldämpfer | Mechanic | 3 | Am Feuer | 220 P |
| Erweitertes Magazin (+50 %) | Mechanic | 3 | Am Feuer | 250 P |
| Kompensator (−35 % Rückstoß) | Mechanic | 4 | Die Linie halten | 320 P |
| Schnellverschluss (−20 % Nachladezeit) | Mechanic | 5 | Die verlorene Lieferung | 350 P |
| Präzisionslauf (−30 % Streuung, +20 % Reichweite) | Mechanic | 6 | Eine ruhige Hand | 450 P |
| Phantom · Legendär (−24 dB, −30 % Rückstoß) | Secret Vendor | 10 | Ein diskreter Auftrag | 1200 P |
| Belagerungsmagazin · Legendär (+100 %) | Secret Vendor | 12 | Wie ein Uhrwerk | 1400 P |
| Titanenkern · Legendär (+20 % Schaden, +1 Durchschussziel) | Secret Vendor | 16 | Die Schuld der Riesen | 1800 P |

Einsatzlevel = überstandene Wellen + 1. Level **und** abgeholter Questabschluss sind erforderlich; fehlende Voraussetzungen und Inkompatibilitäten stehen rot im Menü. Schalldämpfer passen auf Pistole, MP5, AK-47 und beide Sniper; Titanenkern auf beide Sniper und MG-60. Nahkampfwaffen unterstützen keine Mods. Schalldämpfer machen Schüsse und Mündungsblitze leiser beziehungsweise schwächer; sie ändern keine Zombie-Zielwahl. Der normale Dämpfer senkt die Reichweite um 10 %, größere Magazine verlängern Nachladen um 10 % beziehungsweise 15 %. Der Host prüft Kauf und Montage und synchronisiert Mods, Kampfwerte und Schusseffekte. Die Suite `weapon_mods` prüft Transaktionen, Level-/Questgrenzen, Nachladen, Munitionsschutz und Koop-Zustand.

**Palisadenring.** Der Ring entsteht abschnittsweise: Eine Barrikade zu bauen errichtet auch den zugehörigen Palisadenabschnitt. Ungebaute Abschnitte sind unsichtbar und frei begehbar. Wird die Barrikade zerstört, fällt auch ihr Abschnitt weg. Die Minimap zeigt nur gebaute Wände; die Gegnerwege werden nach Bau und Zerstörung neu berechnet. Der Spieler kann gebaute Torsperren mit der Leertaste überklettern. Prüfung: `--script res://tests/run.gd -- --suite=perimeter --smoke-test --no-intro --no-music`.

Barrikaden binden anrückende Zombies bis zum Durchbruch. Ein sichtbarer Spieler innerhalb von 10 Metern hat jedoch Vorrang: Zombies lösen sich von der Sperre und greifen ihn an. Die Verfolgung bleibt bis 14 Meter bestehen; versperren Wände oder geschlossene Tore die Sicht, nehmen sie die Belagerung wieder auf. Das gilt auch im Koop und für Titanen.

Wellengegner entstehen ausschliesslich ausserhalb des vollständigen Barrikadenrings, mit zwei Metern Abstand zu dessen Rand und Toröffnungen. Das gilt auch bei ungebauten oder zerstörten Abschnitten. Zufällige Waldspawns bleiben erhalten; sowohl die Auswahl als auch die endgültige Position auf dem Wegenetz werden geprüft. Ungültige Punkte werden verworfen, mit den bestehenden sicheren Zugängen als Ausweichmöglichkeit. Prüfung: `spawn_safety`.

Die grosse visuelle Hüttenwarnung wird beim Beginn eines Angriffs von `hut_under_attack.mp3` begleitet. Der Ton ist ortsunabhängig hörbar und spielt einmal pro Alarmphase; weitere Treffer starten ihn nicht neu. Nach fünf Sekunden ohne Treffer endet der Alarm, ein neuer Angriff löst ihn erneut aus. Clients reagieren auf den synchronisierten Alarmzustand; ein später Beitritt spielt keinen alten Warnton ab.

**T** öffnet das Turmbaumenü, maximal sechs Türme pro Team. **R/Mausrad** dreht die Vorschau, **E** bestätigt. Am Turm steigt **E** auf die Plattform und übernimmt die Waffe: Maus zum Zielen, Linksklick zum Feuern, **E** zum Absteigen. Jeder Turm hat einen Bedienplatz, den auch Teammitglieder nutzen können. Unbesetzte Türme feuern automatisch in einem 160°-Sektor; manuell ist Rundumfeuer möglich. **R** richtet einen unbesetzten Turm neu aus, **F** repariert ihn. Ausbau auf Stufe 2/3 und Abbau verwaltet Mechanic; die Kosten skalieren mit dem Turmtyp. Dauerfeuer erzeugt Hitze. Zerstörung oder Tod des Bedieners gibt den Platz frei.

Turm-Zielmodus: Beim Bedienen Rechtsklick halten für sanften Zoom (75° auf 55°), feinere Maussteuerung und 75 % weniger manuelle Winkelstreuung. Linksklick feuert weiterhin. Gilt für alle fünf Turmtypen, auch im Multiplayer; Reichweite, Schaden und Feuerrate bleiben gleich. Loslassen, Menüs, Absteigen oder Tod beenden den Zielmodus.

| Turm | Baupreis | Grundreichweite | Wirkung |
|---|---:|---:|---|
| Wächter | 120 P | 26 m | Standardgeschütz mit Feuerstößen |
| Flammenwerfer | 260 P | 14 m | Feuerkegel gegen mehrere Gegner, durch Wände blockiert |
| Mörser | 380 P | 60 m | Bogenförmige Granatenflugbahn mit Kollision und 6 m Explosionsradius |
| Schweres MG | 450 P | 44 m | Schnelles Dauerfeuer, Überhitzung beachten |
| Teslaspule | 600 P | 22 m | Kettenblitz auf nahe Gegner mit freier Verbindung |

**Reichweite und Schusseffekte:** Beim Platzieren, Ausrichten und neben einem Turm markiert ein goldener, dem Gelände folgender Bogen den 160°-Automatiksektor; die gestrichelte Fortsetzung zeigt die manuelle Rundumabdeckung. Beim Bedienen erscheint der volle Reichweitenkreis. Die Anzeige am Fadenkreuz nennt Zielentfernung, aktuelle Reichweite inklusive Ausbau sowie „in Reichweite“, „ausser Reichweite“ oder eine blockierte Schusslinie. Die Bodenmarkierung zeigt die maximale horizontale Reichweite; Höhe und Hindernisse beeinflussen tatsächliche Treffer. Der Mörser hält seine maximale Zielentfernung auch bei manueller Bedienung ein.

Flammenwerfer verwenden einen durchgehenden, verwirbelten Feuerstrahl mit auslaufenden Flammen. Wächter und MG haben gedämpften Rückstoss, kurze fliegende Leuchtspuren, Mündungsfeuer, Rauch und Hülsenauswurf. Mörser verschiessen sichtbare Granaten mit Feuer-/Staubausbruch; Teslaentladungen glühen und verblassen. Rückstoss bewegt nur das Waffenmodell, nicht Sitz oder Trefferberechnung. Sichtprüfung und Effekttests: `--suite=tower_effects --smoke-test --no-intro --no-music --render-towers` → `artifacts/tower-effects/`.

Der Host prüft Baupreis, Platzierung, Belegung und manuelle Schüsse. Turmtyp, Bediener, Feuer und Kettenblitze werden synchronisiert. Automatisierte Prüfungen: `towers`, `defence` und `multiplayer`; gerenderte Ansichten: `tower_visuals`.

Die vier Spezialtürme verwenden die bereitgestellten Aufnahmen `flamethrower_tower.mp3`, `Machinegun_Tower.mp3`, `Mortar_Tower.mp3` und `Teslacoil_Tower.mp3`. `tools/prepare_tower_audio.py` erzeugt daraus Mono-Spielclips in `assets/audio/sfx/towers/`, mit Quellenprüfsummen in `sources.json`. Das MG spielt pro Schuss einen einzelnen Report samt Ausklang, der Flammenwerfer einen überblendeten Loop mit kurzem Ausblenden, Mörser und Tesla jeweils einen Abschuss-/Entladungsclip. Jeder Turm hat einen eigenen räumlichen Soundgeber mit Entfernungsdämpfung und begrenzter Stimmenzahl. Neue replizierte Schüsse spielen auch auf Clients; alte Schüsse beim Beitritt bleiben stumm. Prüfung: `--suite=tower_effects`.

Ab **Welle 6**, danach alle drei Wellen, kommen rund 27 m grosse Feldtitanen. Ihre orange markierten Flächenangriffe kündigen sich 2,4 Sekunden vorher an. Ab Welle 12 kommen zwei, ab Welle 24 höchstens drei Titanen in diesen Wellen. Alle Systeme unterstützen den Koop. Einzelheiten: [Verteidigungsanleitung](../docs/VERTEIDIGUNG.md).

Beim Titan-Spawn wird eine der vier bereitgestellten Aufnahmen `Titan_spawn_1.mp3` bis `titan_spawn_4.mp3` zufällig ausgewählt. Alle Spieler hören dieselbe Variante sofort auf der ganzen Karte: räumliche Richtung bleibt erhalten, Entfernungsdämpfung und Reichweitenbegrenzung entfallen für diesen Ruf. Der Titan-Mix begrenzt Spitzen und senkt kurz die Musik ab. Andere Titan-Geräusche und Kamerawackeln bleiben entfernungsabhängig; Beitritte spielen alte Spawn-Rufe nicht erneut ab. Prüfungen: `titan_horror` und `titan_mix` (Audioaufnahmen in `artifacts/titan-horror/`).

## Hüttenschlüssel und Türen

**Mechanics verlorene Lieferung:** Die Werkzeugkiste wird pro Runde zufällig im spielbaren Gebiet platziert. Der Ort liegt ausserhalb des Lagers, auf begehbarem Boden, mit freiem Platz und einem Weg vom Lager dorthin; Gebäude, Teich und steile Stellen sind ausgeschlossen. Nach Annahme zeigt die Karte den tatsächlichen Fundort. Der Host synchronisiert Position und Abholstatus, auch für später beitretende Spieler. Innerhalb einer Runde bleibt die Kiste am selben Ort. Prüfung: `delivery_spawn`.

Waldhütte und Holzlager haben je einen eigenen Schlüssel mit **30 % Fundchance pro Auslosung**. Beim Spielstart, bei jeder neuen Welle und zu Beginn jeder Wellenpause wird für noch fehlende Schlüssel gewürfelt. Ihre geprüften Fundstellen liegen in Wegnähe und werden bei jedem neuen Spiel zufällig gewählt. Bereits erschienene Schlüssel bleiben während aller Phasen liegen; eingesammelte Schlüssel erscheinen nicht erneut. Im Umkreis von 16 m erscheinen ein Hinweis, die Entfernung und ein Richtungspfeil; der Schlüssel liegt auf einem niedrigen Baumstumpf. Nahe herangehen und **E** drücken. Wände verhindern die Aufnahme durch Hindernisse.

Gefundene Schlüssel bleiben für das gesamte Spiel im Inventar (**I**), auch über Wellenwechsel hinweg. Der Waldhüttenschlüssel passt zum Garagentor und zur oberen Hüttentür, der zweite zum Holzlagertor. **E** öffnet und schliesst die Türen wiederholt. Beim Öffnen schwingen die Flügel vom Spieler weg, auch wenn er direkt vor der Tür steht. Andere Personen im Schwenkbereich blockieren die Bewegung; beim Schliessen bleibt der Einklemmschutz aktiv. Bereits aufgeschlossene Türen halten Gegner kurz auf, können unter anhaltenden Angriffen aber aufgedrückt werden. Das vergitterte Holzlagerfenster verhindert den Zugang ohne Schlüssel.

## Grafik und Leistung

Der Waldboden trägt eine dichte, niedrige Schicht aus Gräsern und Farnen bis entlang des Wegs zur Hütte. Unregelmäßige Gruppen, unterschiedliche Wuchshöhen und gedämpfte Grün-/Brauntöne lassen Laub zwischen den Pflanzen sichtbar. Wege, Gebäude, Lichtung und Teich bleiben frei. Der Bewuchs folgt dem Gelände und nutzt die Grassichtweite des gewählten Grafikprofils sowie räumliche Instanzgruppen ohne zusätzliche Schatten oder Kollisionen.

Die Felder tragen im Nahbereich eine dichte Grasschicht mit rund 13 Büscheln pro Quadratmeter. Ein leicht versetztes Raster verhindert grosse kahle Lücken; Höhe und Ausrichtung variieren und folgen dem Hang. Der Bewuchs reicht auch über die westlichen Wiesen und etwas über den spielbaren Rand hinaus. Wege, Gebäude und Teich bleiben frei. In der Ferne werden die Büschel allmählich ausgedünnt; die bestehenden Sichtweiten und räumlichen Instanzgruppen begrenzen den Zeichenaufwand.

Strassen und Wege folgen dem triangulierten Gelände mit fein unterteilten Flächen. Unter dem Asphalt liegt durchgehend texturierter Kiesboden, sodass an den Rändern keine blau-grauen Fehlstellen entstehen und an Kreuzungen kein Gelände durch die Fahrbahn ragt.

Die Bauernhäuser und Dorfgebäude in der Ferne besitzen unterschiedliche Putz- und Holzfassaden, Ziegel- oder dunkle Dächer mit Überständen, Fensterläden, Scheunentore, Kamine und Steinsockel. Lage und Ausrichtung folgen weiterhin den Kartendaten. Die Bauteile werden pro Material in räumlichen Gruppen zusammengefasst; Fassaden und Dächer bleiben auch im Grafikprofil «Flüssig» gemeinsam sichtbar.

Der Waldteich mit seinem speisenden Holzbrunnen liegt am östlichen Ende des schmalen nördlichen Fußwegs. Der Weg endet am Westufer; Mulde, Wasserstand und Uferbewuchs folgen der neuen Position. Die frühere Teichstelle westlich der Weggabelung ist wieder Waldboden.

Der Lagerfeuerrauch steigt langsam auf und driftet mit schwachem Wind. Gedämpfte Wirbel, begrenzte Geschwindigkeit und über zehn Sekunden wachsende, weich ausblendende Rauchwolken ersetzen die schnelle Bewegung. Der Rauch reagiert auf die Beleuchtung und blendet an nahen Oberflächen weich aus.

Der Grillplatz ist nach den Standortfotos eine ebene Kiesfläche (das Gelände wird dort auf eine Ebene gezogen): Feuerstelle mit vier Rundholzbänken auf Kies, der Picknicktisch drei Meter westlich auf Laub, der ausgehöhlte graue Holzbrunnen mit dickem Stammpfosten und Eisenrohr am Westrand des Platzes, der weisse Abfalleimer auf einem Pfosten dazwischen, Infotafel und Wegweiser am Eingang des Waldwegs. Die Waldhütte hat ein Satteldach mit Ost-West-First: der Giebel mit weitem Vordach auf Pfetten und Kopfbändern zeigt zum Weg im Westen, die Aussentreppe aus Betonblöcken führt ohne Geländer der Nordseite entlang zur oberen Tür, in der Westwand sitzen zwei Kellerfenster. Das Holzlager steht mit 14 Grad Drehung wie im Luftbild, mit hellem Faserzementdach und weitem Vordach auf Streben zur Strasse; das grosse Tor liegt nahe der Südostecke. Entlang des Wegs zur Hütte gibt es wie auf den Fotos keinen Zaun, nur den Drahtzaun östlich der Sennhofstrasse. Südlich des Wegs Richtung Dorf und westlich des Feldwegs West liegen offene Felder bis zum Kartenrand. Die Häuser von Sennhof und Remetschwil am Horizont sind Bauernhäuser: weisse ein- bis zweistöckige Häuser mit steilen Ziegeldächern, dunkle Holzscheunen und lange Bauernhäuser mit angebauter Scheune. Der Wegweiser am Waldweg zeigt oben nach Oberrohrdorf (Norden) und unten nach Remetschwil (Süden); an der Abzweigung der Sennhofstrasse steht ein zweiter (Waldhütte Remetschwil, Oberrohrdorf, Remetschwil). Die Dörfer sind gegen das swissimage-Luftbild (dieselben Bilder wie Google Maps) abgeglichen: Dachfarbe, Firstrichtung und Flachdächer jedes Hauses kommen aus dem Luftbild, die Bäume um die Höfe stehen wo im Luftbild Kronen sind, auf dem Sennhof stehen Siloballen, ein Traktor und Autos. Die Waldhütte hat rotbraune, horizontale Nut-und-Feder-Bretter und ein dunkelgraues Wellfaserzement-Dach wie auf den Fotos; die Baumkronen haben pro Baum leicht andere Farbtöne, einzelne Bäume vergilben schon (September), und Gegenlicht scheint durch das Laub. Brunnen, Abfalleimer, Wegweiser, Infotafel, Feuerstelle mit Schwenkgrill, Bänke, Picknicktisch, der liegende Baumstamm, die Werkbank in der Garage sowie Munitionskisten, Munitionspakete und Verbandspäckli sind Meshy-PBR-Modelle (2K-Texturen); fehlt ein Modell, baut das Spiel die alte Box-Version. Die Zugänge zum Garagentor und zur Aussentreppe bleiben frei. Gesammelte Steinpilze und Fliegenpilze verschwinden sofort vollständig und werden genau einmal im Inventar verbucht. Ihre Modelle bleiben auch nach der Kartenoptimierung mit dem Sammelobjekt verbunden.

Der aktuelle Standard startet um **06:00 Uhr** und lässt die Zeit über Wellenwechsel hinweg weiterlaufen. Ein vollständiger Zyklus dauert **15 echte Minuten**: **10½ Minuten** von Morgen bis Abend (05–20 Uhr), **4½ Minuten** Nacht (20–05 Uhr). Die Nacht ist damit 20 % kürzer, die helle Tagesphase 12 % länger. Die Uhr zeigt die jeweils aktuelle Zeitgeschwindigkeit. Die Ortszeit steht oben rechts; Morgen, Tag, Abend und Nacht gehen weich ineinander über. Pause, Inventar, Skills, Barrikadenplanung und Spielende halten die Uhr an.

Sonnenstand, Himmelsfarben, Bergpanorama, Nebel und die Beleuchtung von Händen/Waffen folgen der Uhr. Nachts werden Feuer und die vorhandenen Hütten-/Laternenlichter stärker, die Umgebung wird dunkler. Die Taschenlampe bleibt mit **F** steuerbar. Die vorhandenen Schatten- und Volumennebelbudgets bleiben erhalten. Lichtwerte werden mit 10 Hz aktualisiert, Himmelsreflexionen alle 30 Spielsekunden mit einer kleinen, über mehrere Bilder verteilten Berechnung.

Die parallel entwickelte Variante mit durchgehendem 15-Minuten-Tag ist inzwischen Standard. `RemZ.exe -- --continuous-day-night` wählt diesen Modus weiterhin ausdrücklich. Ein langsamerer Zyklus mit Morgenstart je Welle lässt sich im `DayNightCycle` über `time_scale = 10.0` und `reset_each_wave = true` einstellen; die Gewichtung von Tag und Nacht bleibt dabei erhalten.

Der Kartenhorizont verwendet ein echtes Schweizer Alpenpanorama von Andreas Mischok / Poly Haven (CC0), mit entfernter Bergkette und Dunst über den Tälern. Der Wald hat dichteren, kühleren Entfernungsnebel. Berge und Tageshimmel werden im vorhandenen Himmelspass gezeichnet: keine zusätzlichen Bergmodelle, Partikel, Schatten oder Viewports. Die 4K-HDR-Textur benötigt mit BC6H und Mipmaps rund 10,7 MiB GPU-Speicher. Quellen: `assets/sky/SOURCES.md`.

Der frühere Vergleich des statischen Alpenhimmels an drei festen Blickpunkten ergab 0,001–0,039 ms zusätzliche GPU-Zeit (unter 1 %) und identische Zeichenaufrufe. Diese Messung stammt vor dem Tag-Nacht-Zyklus. Sie ist keine Garantie für unveränderte FPS auf jeder Hardware oder für 100 FPS im Kampf. Details stehen in `PERFORMANCE.md`.

Im Start- und Pausenmenü stehen drei Grafikprofile, Bildratenlimit, VSync, FPS-Anzeige, Mausempfindlichkeit und Lautstärke zur Verfügung. Änderungen werden lokal gespeichert. Das Profil **Flüssig** verwendet reduzierte Effekt- und Sichtweiten sowie 85 % 3D-Auflösung mit FSR; die Oberfläche bleibt scharf. Die Standardbegrenzung beträgt 144 FPS.

Die Physik verwendet Jolt. Vegetation und wiederholte Objekte werden räumlich gruppiert und außerhalb der Sichtweite ausgeblendet. Gegner berechnen ihre Wege zeitlich versetzt. Maximal 48 lebende Gegner bleiben gleichzeitig aktiv; weitere Spawns warten in der Welle.

Die 72 separaten Oberflächentexturen verwenden jetzt GPU-Kompression und Mipmaps. Ihre Desktop-Importdateien belegen zusammen etwa 64 MiB einschließlich Mipmaps; die unkomprimierten RGBA-Basisbilder entsprechen etwa 246 MiB. Farbkarten verwenden BC7, Normalmaps die passende Normalmap-Kompression.

Bleiben nach dem letzten Spawn höchstens drei Zombies für 20 Sekunden übrig, suchen sie aktiv den Spieler. Sie geben alte Belagerungsziele auf und aktualisieren ihren Weg jede Sekunde. Sperren auf dem Weg werden weiterhin angegriffen. Im Koop suchen sie einen lebenden Spieler; die Entscheidung trifft der Host.

Das **Feldmesser** gehört zur Startausrüstung (Taste **0**): 55 Schaden, 0,42 Sekunden Schlagabstand und 1,85 Meter Reichweite. Die **Waldaxt** verkauft Vendor für **180 Punkte**, sobald Welle 1 und der Ankunftsauftrag abgeschlossen sind: 125 Schaden, 0,95 Sekunden Schlagabstand und 2,35 Meter Reichweite. Auswahl über Mausrad oder Inventar (**I**), Angriff mit **Linksklick oder H**. Beide brauchen keine Munition; Wände blockieren Schläge. Bei gezogener Nahkampfwaffe versorgen Munitionsfunde die zuletzt ausgewählte Schusswaffe. Das gilt auch im Koop.

Der **Waldläufer .308** besitzt ein **4×-Zielfernrohr**: rechte Maustaste halten, um durch eine runde Optik mit Fadenkreuz zu zielen. Die Spielwelt wird tatsächlich vierfach vergrößert; das Waffenmodell verdeckt die Linse nicht. Loslassen, Nachladen und Waffenwechsel verlassen die Scope-Ansicht. Die Suite `sniper_scope` prüft die projizierte Vergrößerung und diese Übergänge; `--render-scope` speichert Vergleichsbilder in `../artifacts/sniper-scope/`.

Quests zeigen ihre benannte Reihe, die Schrittfolge, den zuständigen NPC und bei Sperren den konkret fehlenden Auftrag samt nächstem Schritt. Waffenberechtigungen werden erst nach Abgabe aller Aufträge einer Reihe freigeschaltet:

- **Marksman:** „Eine ruhige Hand“ (15 Kopfschuss-Kills) → „Präzision unter Druck“ (25 Kopfschuss-Kills und Welle 3) bei Vendor → „Ein diskreter Auftrag“ (40 Kopfschuss-Kills) beim Secret Vendor. Erlaubt den Kauf von Waldläufer .308 und Titanenbrecher .50; letzterer benötigt zusätzlich den Titanenauftrag und Welle 9.
- **Sturm:** „Die Linie halten“ → „Die lange Schicht“. Kaufberechtigung für die AK-47.
- **Verteidigungstechnik:** „Der erste Wächter“ → „Kreuzfeuer“ → „Doppelt hält besser“ → „Wie ein Uhrwerk“. Kaufberechtigung für das MG-60; Lieferung und Welle 5 bleiben zusätzliche Voraussetzungen.

Die Berechtigung ersetzt keinen Kauf. Ziele zählen im Koop gemeinsam, jeder Spieler nimmt seine Aufträge selbst an und holt seine Belohnungen ab. Kopfschüsse mit Pistole oder Revolver zählen für die Marksman-Reihe; eine noch gesperrte Waffe ist dafür nicht nötig.

**Quest-Balancing:** Das Einsatzlevel dieser Runde entspricht **1 + überstandene Wellen**. Es ist kein dauerhaftes XP-Level. Mindestlevel werden im Händlerkopf, in jeder Quest und in Sperrhinweisen angezeigt. Außer „Am Feuer“ verlangt jeder Auftrag nach seiner Annahme mindestens eine zusätzliche überstandene Welle. „Wie ein Uhrwerk“, „Das letzte Licht“ und „Ein Name, den keiner kennt“ verlangen zwei. Bereits erreichte Teamziele bleiben anrechenbar, ermöglichen aber keine sofortige Abgabe aufeinanderfolgender Quests. Die Annahmewelle wird pro Spieler gespeichert und im Koop synchronisiert.

| Reihe | Mindestlevel je Schritt | Frühester Reihenabschluss |
|---|---|---|
| Sturm | 2 → 5 | nach Welle 5 |
| Marksman | 2 → 5 → 8 | nach Welle 8 |
| Verteidigungstechnik | 2 → 4 → 7 → 10 | nach Welle 11 |
| Waldwache | 2 → 5 → 8 | nach Welle 8 |
| Versorgung | 4 | nach Welle 4 |
| Titanenjagd | 7 → 11 → 16 | nach Welle 17 und erfüllten Titanenzielen |
| Das Lager bewahren | 11 | nach Welle 12 |

Die Mindesttermine setzen rechtzeitige Annahme und erfüllte Ziele voraus. Wer einen Auftrag später annimmt, muss die zusätzlichen Wellen ab diesem Zeitpunkt überstehen. So wird etwa der Waldläufer trotz seiner niedrigeren allgemeinen Waffen-Wellenanforderung erst nach Abschluss der Marksman-Reihe ab Welle 8 kaufbar. `quest_balance`, `extra_quests` und `progression` prüfen Stufen, persönliche Wartebedingungen, Ziele und die Kaufberechtigungen.

## Prüfen und exportieren

Aus dem übergeordneten Projektordner in PowerShell:

```powershell
./tools/check-game.ps1 -Mode Smoke
./tools/check-game.ps1 -Mode WeaponEffects
./tools/check-game.ps1 -Mode Barricades
./tools/check-game.ps1 -Mode Defence
./tools/check-game.ps1 -Mode Atmosphere
./tools/check-game.ps1 -Mode DayNight
./tools/check-game.ps1 -Mode DoorsKeys
./tools/check-game.ps1 -Mode CampsitePickups
./tools/check-game.ps1 -Mode Benchmark -Quality 0
./tools/check-game.ps1 -Mode ExportWindows
```

Bei anderem Installationsort zusätzlich `-Godot 'C:/Pfad/Godot.exe'` angeben. Für den Export sind passende offizielle Windows-Templates erforderlich; das Preset verweist auf `../builds/templates/`. Benchmark mit geschlossenem weiteren Spielfenster durchführen. Der Benchmark verändert keine gespeicherten Einstellungen.

Die 56 automatisierten Smoke-Prüfungen decken Start, Navigation, Grafikprofile, Minimap-Ausrichtung, Hände und Kamerafreiraum für alle neun Waffen, unabhängige Handdarstellung und Mündungsfeuer, Munition, Feuerrate bei 30/60/144 FPS, Barrikaden, Nahkampfsichtlinie, Wellen, Granaten, Pause, Fähigkeiten und Neustart ab. Visuelle Prüfungen aller Waffen: `--script res://tests/run.gd -- --suite=visual --smoke-test`.

`WeaponEffects` prüft zusätzlich alle fünf Waffen beim Schießen, Rauchabbau, Rückstoßrichtung und Rückkehr, Dauerfeuer, leere Magazine, Nachladen, Waffenwechsel, Stoffbewegung beim Laufen, Pause, langsame Frames und Zielen. Der gerenderte Lauf umfasst 50 Funktionsprüfungen und 11 Screenshot-Prüfungen. Bilder: `../artifacts/weapon-effects/`.

`Barricades` umfasst 54 Prüfungen einschließlich gerenderter Ansichten: vollständige Linien, Kosten, Vorschau, Kollision an den Verbindungen, Upgrades, Reparatur, Zerstörung und Wiederaufbau, blockierte Bauflächen, Reichweite sowie Kamera-/Menürückkehr. Ansichten aller vier Zugänge und des Menüs bei 1280×720 liegen in `../artifacts/barricades/`.

`Atmosphere` prüft Himmel, Nebel und die drei Grafikprofile. Es erstellt elf Vergleichs-/Himmelsansichten und misst den alten und neuen Himmel in der Reihenfolge vorher–nachher–nachher–vorher aus drei unveränderten Kamerapositionen. Aufwärmen und Screenshots liegen außerhalb der Messintervalle. Bilder und Messdaten: `../artifacts/atmosphere/`.

`DayNight` prüft Zeittempo bei 30/60/144 FPS, Mitternacht, Wellenneustarts, alle Pausenmenüs, Nachtbeleuchtung und Grafikprofile. Es erstellt Ansichten von Morgen, Mittag, Abend, Nacht und Taschenlampe sowie einen Vergleich mit stehender/laufender Uhr. Bilder und Messdaten: `../artifacts/day-night/`. Ohne Fenster kann die Funktionsprüfung mit `--headless --script res://tests/run.gd -- --suite=day_night --smoke-test --no-music` ausgeführt werden.

`DoorsKeys` prüft zufällige erreichbare Fundorte, Entfernung und Sichtlinie bei der Aufnahme, Schlüsselbesitz, Türdurchgänge, Öffnen/Schliessen, Pause, Einklemmschutz, Gegnerdruck und Inventar. Zusätzlich werden alle drei Türen aus 0,5 m Entfernung von beiden Seiten über die tatsächliche E-Interaktion geöffnet und geschlossen; ein anderer Akteur hinter dem Tor muss die Öffnung weiterhin blockieren. Bilder: `../artifacts/doors-keys/`. Reproduzierbare Fundorte sind mit `--key-seed=17` möglich; ohne Parameter werden sie bei jedem Spielstart neu ausgewählt.

`CampsitePickups` prüft alle zehn Pilzarten nach der Kartenoptimierung: sofortiges Ausblenden, vollständiges Entfernen des Modells, einmalige Inventarbuchung und unveränderte übrige Pilze. Ansichten von Feuerstelle, Brunnen und Pilzen vor/nach dem Sammeln: `../artifacts/campsite-pickups/`.

### Pilze und Verkauf

**Autorefill** steht bei Vendor und Secret Vendor oben im Reiter **Handel**. Es füllt Magazine und Reserven aller eigenen Schusswaffen bis zum jeweiligen Limit oder soweit das Guthaben reicht. Die aktuelle bzw. zuletzt geführte Schusswaffe hat Vorrang; pro Waffe wird zuerst das Magazin gefüllt. Berechnet wird die tatsächlich gelieferte Schusszahl anteilig zum Preis der bisherigen Zwei-Magazin-Pakete, auf volle Punkte pro Waffe aufgerundet. Die Anzeige nennt den Komplettpreis und die mit dem aktuellen Guthaben mögliche Auffüllung. Granaten werden separat gekauft. Bereits volle Vorräte kosten nichts; im Koop bestätigt der Host die Buchung.

Schwere Waffen besitzen **Durchschuss**: Waldläufer .308 trifft bis zu **3 Zombies** mit jeweils **75 % Restschaden**, Titanenbrecher .50 bis zu **5** mit **80 %**, MG-60 bis zu **2** mit **65 %**. Der erste Treffer verursacht vollen Schaden; die Abschwächung wird für jedes weitere Ziel erneut angewendet. Jeder Zombie wird pro Geschoss nur einmal getroffen, auch bei überlappenden Körper-Hitboxen. Kopfschüsse, Entfernung und Titanenbonus werden pro Ziel ausgewertet. Wände, Gelände und Türme stoppen das Geschoss. Die Werte stehen auch beim Händler und in den Inventardetails. Die Suite `piercing` prüft echte Trefferketten, Schaden, Munition, Trefferstatistik und Koop-Zuordnung.

**Geld teilen:** Mit **B** wirfst du 100 Punkte als sichtbares Geldbündel nach vorne; bei weniger Guthaben den Restbetrag. Mitspieler sammeln es durch Darüberlaufen ein. Der Werfer kann es nach zwei Sekunden wieder aufnehmen. Geld bleibt bis zur Aufnahme oder zum Rundenende liegen. Im Koop bestätigt der Host Abzug und einmalige Gutschrift; der Betrag wird nicht als neu verdienter Abschusslohn gezählt. Das Inventar liegt jetzt auf **I**. `cash_drops` prüft Geldtransfer, Bestandsgrenzen, Wurfphysik und die Synchronisierung der Bündel.

Zehn Pilzsorten wachsen mit unterschiedlicher Häufigkeit im Wald. Mit **E** sammeln, im Inventar (**I**) zum Essen anklicken. Aktive Effekte und Restlaufzeit stehen im HUD und Inventar. Heilung aktualisiert sofort den Lebensbalken; reine Heilpilze bleiben bei voller Gesundheit erhalten.

| Pilz | Spieleffekt | Verkauf |
|---|---|---|
| Steinpilz | +25 Leben | 8 P |
| Fliegenpilz | −15 Leben, 20 s doppelter Waffen-/Nahkampfschaden | 14 P |
| Pfifferling | +10 Leben, 30 s +20 % Lauftempo | 10 P |
| Morchel | +15 Leben, 30 s −25 % Nachladezeit | 14 P |
| Maronenröhrling | +40 Leben | 12 P |
| Parasol | +15 Leben, 30 s −25 % erlittener Schaden | 12 P |
| Reizker | +10 Leben, 40 s doppelte Regeneration | 10 P |
| Tintenpilz | 35 s −35 % Waffenstreuung | 16 P |
| Violetter Rötelritterling | +5 Leben, 40 s +35 % Waffen-/Nahkampfschaden | 18 P |
| Krause Glucke | +60 Leben | 22 P |

Pilze verändern permanente Trainingswerte nicht. Gleichartige Boni verwenden den stärksten aktiven Effekt; erneutes Essen derselben Sorte erneuert ihre Laufzeit. Solo pausiert das Inventar auch die Effekte, im Koop laufen sie weiter. Tod entfernt die zeitlichen Boni. Der Host verwaltet Wirkung, Verbrauch und Verkauf für jeden Spieler getrennt.

Bei **Vendor und Secret Vendor → Verkaufen** lassen sich einzelne Pilze, Granaten (15 P), volle Reservemagazine und gekaufte Waffen (35 % des Kaufpreises) verkaufen. Restmunition einer verkauften Waffe bringt keinen zusätzlichen Erlös; Reserve vorher separat verkaufen. Pistole und Feldmesser bleiben als Startausrüstung erhalten, ebenso bereits erworbene Questberechtigungen. Mara vergibt Waldaufträge; Mechanic betreut Training und Türme. Beim Öffnen von Maras Gespräch ertönt ihre Begrüssung passend zur Spieluhr: Morgen 05–09 Uhr, Hello 09–17 Uhr, Abend 17–20 Uhr, Nacht 20–05 Uhr. Die Stimme spielt lokal für den Gesprächspartner und auch während der Solo-Pause.

`mushroom_trade` prüft Heilung, Boni, Ablauf, Training während eines Effekts, Verkaufspreise, Bestandsgrenzen, Entfernung und Koop-Zustand. Mit `--render-mushrooms` entstehen Inventar- und Händleransichten in `../artifacts/mushrooms/`.

## Stand der Freigabe

Dies ist ein spielbarer Entwicklungsstand mit Windows-Export, keine bestätigte Verkaufsfreigabe. Dauerhaft 100 FPS sind für den neuesten Kartenstand noch nicht unter störungsfreien Bedingungen nachgewiesen. Asset-Nutzungsrechte, längere Spieltests und Tests auf weiterer Hardware stehen vor einem Verkauf aus. Die vorhandenen Musik- und Sounddateien stammen laut ihren Skripten aus der Bibliothek des Nutzers; Lizenzbelege liegen hier nicht vor.

**Hüttennachschub:** Munitions- und Waffenfundstellen in Waldhütte und Holzlager werden zu Beginn jeder Welle aufgefüllt. Nicht eingesammelte Vorräte stapeln sich nicht. Munitionskisten geben ab Welle 1/5/9/13 jeweils 1/2/3/4 Magazine für die gewählte Waffe. Ab Welle 3 kommen MP5 und Schrotflinte hinzu, ab Welle 8 der Waldläufer. Waffenfunde erfordern die gleichen Quest-Berechtigungen wie beim Händler; bereits besessene Waffen liefern passende Munition. Volle Reserven lassen die Fundstelle liegen. Im Koop teilen sich alle Spieler den Bestand; geöffnete Türen bleiben geöffnet.

**Meshy-Modelle für Krähe und Nahkampf:** `tools/meshy_raven_melee.py` erzeugt drei fortsetzbare Meshy-7.1-Aufträge mit 2K-Geometrie und 4K-PBR-Texturen; Originale und Belege unter `meshy_output/raven_melee/`. `tools/prepare_raven_melee.mjs` normalisiert die echten Geometrien auf Spielmaße, optimiert Texturen und versieht die Krähe mit einem Flügel-Rig. Die Modelle unter `assets/models/*_real.glb` werden sowohl in der Egoansicht als auch für Mitspieler verwendet. Raven-Rufe stammen aus `assets/audio/sfx/raven_1.mp3`, `raven2.mp3` und `raven3.mp3`, wechseln ohne direkte Wiederholung und haben 45 m Hörweite.

**Vogelscheuchen:** Das Maislabyrinth trägt keine schwebende Beschriftung. Alle vier Vogelscheuchen verwenden das 2,5 m hohe Meshy-Modell `assets/models/scarecrow_real.glb` mit schädelartigem Kopf, zerrissener Kleidung, Stroh und PBR-Materialien auf einer Holzstütze. Wiederaufnahme der Generierung: `python tools/meshy_raven_melee.py scarecrow_real`; Spielaufbereitung: `node tools/prepare_raven_melee.mjs scarecrow_real`.

**Maisdichte:** Sechs Pflanzen pro Quadratmeter im Feld, acht in den Labyrinthwänden, mit breiterem Blattwerk auf Augenhöhe. Die Gänge bleiben frei. Drei Detailstufen in räumlichen MultiMesh-Gruppen begrenzen den Zeichenaufwand der dichteren Bepflanzung. Jede Gruppe besitzt genau eine aktive Geometrie; der Detailwechsel hat zwei Meter Spielraum gegen ständiges Umschalten beim Laufen. Gemeinsame Sichtbarkeitsgrenzen berücksichtigen die Windbewegung, und feine Blattadern werden auf Distanz geglättet.


**Feuerwerk:** Bei **Vendor → Feuerwerk** gibt es Rubinstern (45 P), Polarlicht (60 P), Goldweide (85 P) und Walddonner-Böller (5 Stück für 35 P). Im Inventar **I** auswählen; **Linksklick** stellt eine Rakete auf und zündet sie bzw. wirft einen angezündeten Böller. **Rechtsklick** oder Mausrad kehrt zur Waffe zurück. Keine Kampfschäden. Raketen benötigen einen ebenen Platz und freien Himmel, steigen nach 1,2 s Lunte auf 34 m und zerlegen nach insgesamt 3,6 s; Böller knallen nach 2,4 s. Drei deterministische Sternenbilder mit Schweifen, Goldregen, Lichtblitz, Rauch und eigenen räumlichen Sounds. Der Knall erreicht die Kamera entfernungsabhängig verzögert.

Maximal 32 Stück in der Feuerwerktasche (8 je Raketensorte, 20 Böller). Pakete werden vollständig gekauft oder ohne Punkteabzug abgelehnt. 0,9 s Zündabstand und maximal 12 gleichzeitige Effekte begrenzen Last und Soundquellen. Bestände gelten für den laufenden Durchgang; im Koop prüft der Host Kauf, Verbrauch, Flugbahn und Abklingzeit. Snapshots übertragen Effektalter und Zufallsseed auch an später beitretende Spieler.

Die echten Meshy-PBR-Modelle liegen unter `assets/models/firework_rocket.glb` und `firework_cracker.glb`. Reproduzierbare Aufbereitung: `tools/meshy_fireworks.py` (fortsetzbare API-Aufträge), `tools/prepare_fireworks.mjs` (Spielmaße, 1K-Texturen), `tools/build_firework_audio.py` (eigene Sounds). Meshy-Belege/Originale unter `meshy_output/raven_melee/firework_*/`. Icons: Suite `render_item_icons` mit `--fireworks-only`. Tests: Suite `fireworks`; mit `--render-fireworks` entstehen Screenshots unter `artifacts/fireworks/`.


**Maisboden:** Das 140 × 52 m grosse Feld folgt der Nordwest-Südost-Richtung des Waldrands. Ein gemeinsames Bodenmesh folgt exakt den Dreiecken des Geländes. Das vorhandene PBR-Erde/Kies-Texturset liefert kleine Steine, Blattreste, Normalen, Rauheit und Umgebungsverdeckung. Sanfte Farbvariation und feine Furchen brechen Wiederholungen; Laufwege sind geglättet, der Aussenrand blendet weich in die Wiese. Suite `cornfield` prüft Ausrichtung, freie Wege, Navigation und Bodenmaterial; `--render-corn` erzeugt Ansichten unter `artifacts/cornfield/`.

**Schnellzugriff:** Zehn Plätze unten mittig. Im Inventar (I) einen Gegenstand rechts anklicken und einen Platz auswählen, oder direkt auf einen Platz klicken. Rechtsklick auf einen Platz entfernt die Belegung. Waffen, Pilze, Feuerwerk, Granaten, Talismane und Spezialmunition sind belegbar. Verbrauchte Items behalten ihren Platz und werden mit Bestand 0 gedimmt; Nachschub ist wieder direkt nutzbar. Die Belegung gilt für die aktuelle Runde.

**Spezialmunition und Laufhändler:** Drachenatem zeigt einen verlängerten Flammenausstoss, glühende Schussspuren und Flammen am getroffenen Gegner. Winterbiss zeigt blaue Schussspuren, Eiskristalle und eine eisige Oberfläche am verlangsamten Gegner. Beide Zustände bleiben bei gleichzeitiger Wirkung sichtbar, auch im Koop. Der Nebelkrämer prüft geplante Wege gegen gebaute Tore und geht bei neu blockierten Wegen zurück.

**Schussspuren:** Frost- und Feuerspuren beginnen für den Schützen an der sichtbaren Laufmündung. Die Umrechnung berücksichtigt die getrennten Waffen-/Weltkameras, ADS und Rückstoss. Der Host-Trefferpunkt bleibt unverändert; andere Spieler sehen die räumliche Schussspur. Prüfung: `--suite=muzzle_alignment`, optional `--render-muzzle`.

Wildtiere sind jagdbar: Rehe, Hirsche, Krähen und Eulen nehmen Schaden durch Schusswaffen, Nahkampf, Turmschüsse und Explosionen. Der erste Abschuss schaltet den Teamerfolg «Jäger» frei (+25 P). Tiere zählen nicht als Zombie-Kills. Fleisch mit E aufnehmen: Hirsch 4, Reh 3, Vogel 1 Portion. Am Lagergrill bei der Waldhütte startet E die Zubereitung einer Portion (6 Sekunden; ein Auftrag pro Spieler). Fertiges Fleisch landet im Inventar; Klick oder belegter Schnellzugriff heilt 35 Leben, bei voller Gesundheit ohne Verbrauch. Verkauf bei Vendor/Secret Vendor: roh 12 P, gegrillt 20 P. Der Host verwaltet Treffer, einmalige Beute, getrennte Vorräte und Grillzeiten; später Beitretende erhalten Tierzustände und verbliebene Beute. Eine neue Runde setzt die Jagd zurück.

**Goldröhrling:** Extrem seltener elfter Pilztyp, reiner Verkaufsfund für 1000 Punkte bei Vendor oder Secret Vendor. Pro Runde besteht eine Chance von 5 % auf genau einen Fund an einer zufällig ausgewählten freien Waldstelle. Der Host entscheidet über Vorkommen und Position; Einsammeln ist einmalig und auch für später Beitretende synchronisiert. Der Fund kann weder gegessen noch als Verbrauchsgegenstand im Schnellzugriff belegt werden. Optik: goldene Materialvariante des vorhandenen detaillierten Meshy-Röhrlings, mit eigenem gerendertem Inventarsymbol.

Forest gravel roads: gravel and dirt use the terrain PBR blend directly, with earthy wear and received shadows; the old overlaid slabs are removed (asphalt keeps its ribbon). Meshy forest_gravel_cluster supplies small 3D stones, deterministically scattered in 24 m MultiMesh chunks and culled beyond 48 m; decorative only, no navigation/collision changes. Meshy receipts are retained under meshy_output; tools/meshy_gravel.py resumes the asset job.

Maislabyrinth-Verstecke bleiben nach dem Einsammeln als unsichtbare, erneuerbare Fundstellen erhalten. Der Host/Einzelspieler plant die Rückkehr nach zufällig 2–4 weiteren Wellen. Alle vier Wellen steigt die Beute bis Stufe 4 (Welle 16): Spezialmunition 12–36, Geld 250–750 P, Granaten 1–3, Munition 2–6 Magazine; Inventarlimits gelten weiterhin. Multiplayer-Snapshots synchronisieren Verfügbarkeit, Bestückungswelle und Rückkehrwelle auch für später beitretende Spieler.

Waldhütte reparieren: maximal 500 HP je Aktion, Preis 30 + 5 × (Welle − 1) Punkte (mindestens Welle 1; abgeschlossene Wellen zählen auch zwischen Angriffen). Fehlende Teilmengen werden proportional und auf volle Punkte aufgerundet berechnet. Interaktionshinweis und Host-Transaktion verwenden denselben aktuellen Kostenvoranschlag.

Feuerwerksbatterien: Sternenfest (650 P, 36 Schüsse über 40 s, Taschenlimit 2) und Himmelsfestival XL (1400 P, 84 Schüsse über 90 s, Taschenlimit 1) bei Vendor kaufen und über Inventar/Schnellzugriff auswählen. Linksklick stellt die Box auf ebenem, freiem Boden auf und zündet sie nach 1,2 s Lunte. Farbige Fächersalven, schnelleres goldenes Finale, bestehende Abschuss-/Knall-/Knistersounds, kein Kampfschaden. Maximal zwei aktive Batterien; noch sichtbare Salven werden beim Multiplayer-Beitritt aus der gemeinsamen Zeitachse rekonstruiert. Meshy-Modelle und PBR-Texturen: tools/meshy_firework_batteries.py, Originale und Belege unter meshy_output.

**Hordenleistung:** Vorbereitete animierte Trefferzonen, gezieltere KI-/Turmabfragen, günstigere Bodenkollisionen, vorbereitete Zombie-Grafik beim Laden und wiederverwendete Tesla-Blitzpuffer senken Spawn- und Kampfspitzen. Grafikprofile und aktive Gegnerlimits bleiben unverändert. Messwerte, Grenzen, Regressionstests und Pflege der Trefferbibliothek: [Performance und Stresstests](../docs/PERFORMANCE.md).

**Erdwurmwellen ab Welle 12:** Zwei neue Meshy-Würmer (14/19 m) graben sich von den Feldern heran. Erdspuren, Warnringe, animiertes Auftauchen/Angreifen/Abtauchen, verwundbare Kampfphasen und die drei Earthworm-Aufnahmen sind auch im Koop synchronisiert. Boss-, Titan- und Wurmbudgets werden gemeinsam begrenzt. Ablauf, Werte, Herkunft der Modelle/Animationen und Prüfungen: [Erdwurmwellen](../docs/EARTHWORMS.md).
