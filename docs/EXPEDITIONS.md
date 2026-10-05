# Expeditionen auf Forest und Planes

Die Umsetzung erweitert beide vorhandenen Survival-Maps. Im Koop verwaltet der Host
Schaden, Vorräte, Aufträge, Bauten und Belohnungen; Clients senden Anfragen. Persönliche
Fortschritte laufen über den bestehenden zuverlässigen, fortlaufend nummerierten
Belohnungskanal. Prüfungen verwenden eigene Speicherordner und Testprofile.

Der aktuelle Quellstand verwendet **Protokoll 8**, Build `remz-dev-20261005-player-experience`
und Menüversion **Co-op 2026.10.05-F**. Alle Mitspieler müssen gemeinsam aktualisieren;
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

Der Einstieg beginnt mit einem einzelnen Ziel: den **Vendor im Lager** aufsuchen.
Seine freiwillige, wiederholbare Einführung erklärt nacheinander Ausrüstung,
die gewählte Klasse, das Feldbuch und den Bau auf der jeweiligen Map. Nach dem
Gespräch erscheinen einzelne praktische Hinweise im passenden Moment; erledigte
Lektionen werden im Profil gemerkt. Erfahrene Spieler können die Einführung und
weitere Hilfen überspringen. Der Auftragstracker zeigt jeweils den nächsten Schritt;
die vollständigen angenommenen Aufträge bleiben im Feldbuch und beim Auftraggeber.

**K** öffnet das Expeditionsfeldbuch, **Z** aktiviert die Klassenaktion. Beide Tasten
folgen dem auf der Tastatur aufgedruckten Buchstaben. **Z** funktioniert daher auch
auf QWERTZ, ohne auf Y auszuweichen, und bleibt beim Sprinten mit Shift benutzbar.
Texteingaben, Menüs, Bauvorschau und Drohnensteuerung lösen keine Klassenaktion aus.
Assassin verwendet weiterhin **V** für den gewählten Teleport. **E** führt genau die
angezeigte nahe Interaktion aus; ein Tastendruck kann nicht gleichzeitig eine Kiste
einsammeln und den benachbarten Händler öffnen.

Das Feldbuch ist ausserdem über das **Pausenmenü** erreichbar. Seine fünf Seiten
sind Überblick, Augmente, Team, Entdeckungen und Expedition. Optionale Listen und
Durchlaufcodes sind aufklappbar; Lagerdienste, Reparaturen, Feuerlöschen und
Schiessserien erscheinen beziehungsweise werden benutzbar, wenn ihr Kontext passt.
Die Klassenkarte erklärt die eigene Fähigkeit und zeigt ihre Abklingzeit. Neue
Augmentangebote erhalten eine Markierung in der Navigation. Solo pausiert beim
Lesen; Koop läuft weiter. Escape kehrt zum vorherigen Spiel- oder Pausenzustand
zurück, einschliesslich Tastaturfokus. K in einem bearbeitbaren Codefeld ist eine
Texteingabe. Das Laden eines Spielstands verlangt eine Bestätigung.

Die permanente Tastenkürzelliste am oberen Bildrand entfällt. Waffenname und
Munition sitzen kompakt am unteren rechten Rand; unbenutzte Nachladeanzeigen bleiben
ausgeblendet. Der Bereich für Pistole und Waffenmodell bleibt dadurch frei. Minimap,
Schnellzugriff, Menüs und Waffenfeld werden auch auf einer 720p-Zeichenfläche getrennt
gehalten. Klassenaktionen erhalten während ihrer Wirkung beziehungsweise Abklingzeit
gezielte Rückmeldung. Weitere Steuerung ist im Pausenmenü nachlesbar.

**Enter** startet eine Welle nur aus der laufenden Spielsteuerung. Eine Bestätigung
im Menü, beispielsweise auf «Weiter», startet nicht zusätzlich die nächste Welle.

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

Die aktuellen Prüfmethoden, bestätigten Ergebnisse und noch offenen Freigabeprüfungen
stehen im [Bericht zur Bedienungsüberarbeitung](PLAYER_EXPERIENCE_VALIDATION.md).
Der [historische Expeditionsbericht](EXPEDITION_VALIDATION.md) dokumentiert die
vorherige Veröffentlichung. Screenshots und vollständige Logs liegen lokal unter
`artifacts/expansion-tests/`, `artifacts/fieldbook-polish/` und
`artifacts/player-experience/`.
