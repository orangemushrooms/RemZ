# Expeditionen auf Forest und Planes

Die Umsetzung erweitert beide vorhandenen Survival-Maps. Im Koop verwaltet der Host
Schaden, Vorräte, Aufträge, Bauten und Belohnungen; Clients senden Anfragen. Persönliche
Fortschritte laufen über den bestehenden zuverlässigen, fortlaufend nummerierten
Belohnungskanal. Prüfungen verwenden eigene Speicherordner und Testprofile.

Die Veröffentlichung verwendet **Protokoll 8**, Build `remz-dev-20261005-expeditions`
und Menüversion **Co-op 2026.10.05-E**. Alle Mitspieler müssen gemeinsam aktualisieren;
ältere Versionen werden beim Beitritt abgewiesen.

## Vollständige Funktionsliste

- [x] Durchlaufcodes mit Startwert, Map, Schwierigkeit, Herausforderung und Prüfsumme.
- [x] Wiederholbare Wellenprofile, Angriffsrichtungen und frühzeitige Funkhinweise.
- [x] Herausforderungen: Pistolen, maximal vier Türme, zehn Wellen mit Finale.
- [x] Aktive Klassenaktionen: Fokus, Unterdrückung, Schockwelle, Zielmarkierung; Assassin-Teleport bleibt verfügbar.
- [x] Drei unterschiedliche Augmente zur Auswahl nach Welle 3, 7, 12, 17 und 22.
- [x] Frostgranaten, Turmüberlastung und kurzer Bonus nach einem Waffenwechsel.
- [x] Sanitäter-, Bewegungs- und Vorratsaugmente.
- [x] Optionale Einsätze: Drohne bergen, Überlebenden eskortieren, Funkstation verteidigen.
- [x] Munition, Verbände und gebraute Drinks weitergeben; nahe Mitspieler heilen.
- [x] Wiederbelebung, Reparatur, Rettung und Heilung in Unterstützungsstatistik und Klassen-XP.
- [x] Kosmetische Klassenmeisterschaft nach Level 30 und Waffenmeisterschaft.
- [x] Chronik, Fundaufzeichnungen und Bestiarium mit Gegenmassnahmen.
- [x] Validierte Spielstände in ruhigen Wellenpausen, einschliesslich Koop-Fortsetzung.
- [x] Forest: abschliessende Funkverteidigung, Sonnenaufgang, Zustandsnote für die Verteidigung.
- [x] Forest: wiederholbare Totem-, Lauf-, Tanz- und Gegnervarianten der Secret Night.
- [x] Forest: variierte Feldprüfungen mit Eliminierungs- oder Halteziel.
- [x] Planes: Fernkampfaufträge für Elitegegner.
- [x] Planes: zwei verteidigbare Aussenposten mit Vorräten je Welle.
- [x] Planes: Lieferwege zwischen Lager, Schiessstand, Händler und Aussenposten.
- [x] Planes: benutzbare Feldtore, Schiessscharten und begehbare Beobachtungsplattformen.
- [x] Planes: zeitbegrenzte Schiessserien, Zielreihenfolgen, Teamwettbewerb und persönliche Rekorde.
- [x] Planes: wiederholbarer Wetterablauf mit Vorhersage.
- [x] Planes: Windrichtung beeinflusst Brände; begrenzter Rauchpool und Löschen mit einem Verband.
- [x] Planes: Senderreihenfolge im Mais, Stationsnotizen und einmalige Vorratsverstecke.
- [x] Planes: abschliessende Evakuierungsverteidigung.
- [x] Planes: reguläre Helme ab Welle 10, Wald- und Maisangriffe, Bossmusik auch ausserhalb jeder fünften Welle.
- [x] Planes: vollständige Rundenübersicht und dauerhafte Leistungsrekorde.
- [x] Leistungswertung unabhängig von ausgegebenen Rem Dollars.
- [x] Getrennte Rekordgruppen nach Map, Herausforderung, Schwierigkeit und Gruppengrösse.
- [x] Begrenzte Beschleunigung bei dauerhafter Verfolgung auf offenem Gelände.
- [x] Normale Grenzen von 40 Türmen und 24 aktiven Gegnern auf Planes bleiben erhalten.
- [x] Englische und deutsche Oberfläche mit gemeinsamen Bedienelementen.
- [x] Automatisierte Regel-, Kampf-, Szenen-, Speicher-, Netzwerk- und Oberflächenprüfungen.

## Bedienung und Regeln

**K** öffnet das Expeditionsfeldbuch, **Z** aktiviert die Klassenaktion, **E** benutzt
ein nahes Einsatzziel. Assassin verwendet weiterhin **V** für den gewählten Teleport.
Das Feldbuch enthält Einsätze, Augmente, Teamvorräte, Chronik, Bauten, Wettervorhersage,
Durchlaufcode, Herausforderungen und Spielstände. Solo pausiert beim Öffnen; Koop läuft
weiter. Die normalen Bau- und Inventarmenüs bleiben über ihre bisherigen Tasten erreichbar.

Ein Code gilt für seine Map. Vor Welle eins kann der Solo-Spieler beziehungsweise Host
den Code übernehmen oder die Herausforderung ändern. Wellen, Wetter und Missionsvarianten
verwenden getrennte Zufallsfolgen. Augmentangebote sind zusätzlich an den Spielernamen
gebunden; damit bleiben sie nach einem erneuten Koop-Beitritt reproduzierbar.

| Klassenaktion | Wirkung | Dauer / Abklingzeit |
| --- | --- | --- |
| Revolverheld | Verbesserte Präzision | 6 s / 30 s |
| Sturmschütze | Schnellere Schüsse; Treffer verlangsamen Gegner | 8 s / 30 s |
| Brecher | Schockwelle im sichtbaren Umkreis von 9 m; 65 Schaden, bei Bossen 35 | Verlangsamung 4 s / 30 s |
| Marksman | Sichtbares Ziel bis 180 m markieren; 25 % mehr eingehender Schaden | 10 s / 30 s |

Eine erfolglose Zielmarkierung verbraucht keine Abklingzeit. Frostgranaten verlangsamen
gewöhnliche Gegner sechs Sekunden, Bosse zwei Sekunden. Turmüberlastung erhöht die
Feuerrate um 25 % und die erzeugte Wärme um 40 %. Der Waffenwechselbonus hält drei
Sekunden und hat acht Sekunden Abklingzeit. Lieferkisten reduzieren das Bewegungstempo
um 20 %. Leichte Ausrüstung erhöht es ohne Kiste um 8 %.

Weitergabe und Heilung benötigen einen lebenden Mitspieler innerhalb von drei Metern
und freie Sicht. Eine Weitergabe verschiebt einen Verband, einen Drink oder bis zu
30 passende Reservepatronen. Heilung kostet einen Verband und heilt bis zu 30 HP,
mit Sanitäteraugment bis zu 45 HP. Unterstützungsbelohnungen werden gegen Wiederholung
geschützt und auf 20 belohnte Ereignisse je Spieler und Welle begrenzt.

Feldtore kosten 100 R, Schiessscharten 90 R, Plattformen 180 R. Eine Reparatur kostet
30 R. Die Plattform besitzt eine begehbare Rampe; ein Tor verweigert das Schliessen,
wenn ein Spieler oder Gegner in der Öffnung steht. Platzierung prüft Gelände, Grenzen,
Kollisionen, Sicht und den Zugang zu Lager, Händlern und Einsatzzielen.

Nach der letzten Welle beginnt eine vorbereitbare Schlussverteidigung. Mindestens ein
lebender Spieler muss innerhalb von 18 m bleiben, damit die 90 Sekunden Haltezeit
laufen. Auch alle vorgesehenen Verstärkungen müssen besiegt sein. Das Ziel besitzt
240 HP. Erst der erfolgreiche Abschluss sichert die Map, auch im Zehn-Wellen-Modus.
Ein zerstörtes Ziel beendet den Durchlauf als Niederlage.

## Spielstände

Gespeichert wird nur in einer ruhigen Wellenpause, mit lebenden Spielern zu Fuss.
Aktive Kämpfe, Einsätze, Feldprüfungen, Granaten, ungesammelte Gegnerbeute, Schiessserien,
Brauvorgänge, Kochen, Drohnen, Feuerwerk und ausstehende Glücksradzahlungen sperren den
Spielstand. Der Host speichert und lädt; alle Mitspieler müssen vorher beigetreten sein
und eindeutige, dieselben Spielernamen verwenden. Geänderte Netzwerk-IDs werden anhand
dieser Namen zugeordnet.

Der Spielstand enthält unter anderem Wellenfortschritt, Durchlaufregeln, Positionen,
Lebenspunkte, Geld, Waffen und deren Kühl-/Nachladezustand, Talente, Augmente, Vorräte,
Aufträge, Statistiken, Wetter, Bauten, Türen, Schlüssel, Beute und zerstörte Requisiten.
Version, Datenformen, Wertebereiche und Prüfsumme werden vor dem Laden geprüft.
Die Datei wird zunächst temporär geschrieben; der vorherige Stand bleibt als Sicherung
erhalten. Das Laden vergibt abgeschlossene Belohnungen nicht erneut.

## Wertung und Nachweise

Kills, Kopfschüsse, Titanen, überlebte Wellen, Präzision und Unterstützung bestimmen
die Leistung. Rem Dollars bleiben ausgebbare Währung. Alte Geldrekorde behalten ihre
alte Kennzeichnung und werden nicht mit den Leistungsrekorden verglichen. Kosmetische
Meisterschaft erhöht die Kampfstärke nach Klassenlevel 30 nicht weiter.

Die reproduzierbaren Prüfbefehle, Ergebnisse und Grenzen stehen im
[Prüfbericht](EXPEDITION_VALIDATION.md). Screenshots und vollständige Logs liegen lokal
unter `artifacts/expansion-tests/`.
