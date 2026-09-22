# Verteidigung und Feldtitanen

**E** baut oder verstärkt direkt an einer Barrikadenlinie; bei Schäden repariert E die Linie. Eine ganze Linie kostet 50 Punkte, Reparatur 25. Drei Stufen mit 300 / 600 / 900 Strukturpunkten; Verstärkungen reduzieren zusätzlich erlittenen Schaden. **V** verweist auf Verteidigungsberatung bei Mechanic. Händler, Einführung und Aufträge: [Fortschritt](FORTSCHRITT.md).

Zombies greifen eine gebaute Linie an, wenn sie ihren Weg zur Hütte versperrt. Sie behalten das Durchbruchsziel beim seitlichen Ausweichen. Gegner aus den vier Anmarschrichtungen berücksichtigen den zugehörigen befestigten Zugang. Nach dessen Zerstörung setzen sie die Verfolgung fort. Eine Linie schützt ihren Zugang; bereits dahinter befindliche Gegner bleiben gefährlich.

## Geschütztürme

- **T** öffnet die Turmauswahl. **R / Mausrad** dreht die Bauvorschau, **Shift+R** dreht zurück, **E** bestätigt, **T / Esc** bricht ab.
- Typen und Baupreise: **Wächter 120 P**, **Flammenwerfer 260 P**, **Mörser 380 P**, **Schweres MG 450 P**, **Teslaspule 600 P**. Höchstens sechs Türme pro Team.
- **E am Turm:** aufsteigen, Maus zum Zielen, **Linksklick** feuert, **Rechtsklick halten** zoomt und verringert die Winkelstreuung um 75 %, **E** steigt ab.
- **R am unbesetzten Turm:** neu ausrichten. **F:** für 35 P reparieren. Ausbau und Abbau bei **Mechanic → Türme**; Preise skalieren mit dem Typ.
- Grundreichweiten: Wächter 26 m, Flammenwerfer 14 m, Mörser 60 m, MG 44 m, Tesla 22 m; jede Ausbaustufe ergänzt 6 m. Bodenmarkierung und Zielanzeige helfen beim Einschätzen von Reichweite und Hindernissen.
- Unbesetzt feuern Türme automatisch im 160°-Sektor, manuell rundum. Dauerfeuer führt zur Überhitzung. Wände und Gelände stoppen Schüsse; Teammitglieder nehmen keinen Turmschaden.
- Zombies und Titanen können Türme zerstören. Hinter einer Barrikade sind sie besser geschützt. Auf der Minikarte erscheinen sie als blaue Quadrate.

## Feldtitanen

Der erste rund **27 m grosse Titan erscheint in Welle 6**, danach alle drei Wellen. Ab Welle 12 erscheinen in diesen Wellen zwei Titanen, ab Welle 24 höchstens drei, jeweils an getrennten Feldpositionen. Die bisherigen Brockenwellen bleiben erhalten. Titanen kommen über die offenen südlichen Felder, mit eigenem geriggtem Modell, schweren Schritten und Bosslebensanzeige.

Vor dem Flächenangriff erscheint eine orange Markierung, die dem Gelände folgt. Sie bleibt am angekündigten Einschlagort; innerhalb der 2,4 Sekunden Vorwarnzeit kann man herauslaufen. Der Einschlag beschädigt Spieler und Verteidigungen im Radius von 8,5 m, gefolgt von einer Erholungsphase. Wände begrenzen den Einschlag und schützen vor der Druckwelle. Unter 40 % Leben wird der Titan schneller. Kugeln und Nahkampfstösse können ihn nicht dauerhaft betäuben. Schwierigkeit, spätere Wellen und Spielerzahl beeinflussen seine Stärke.

Ein Titaneneinschlag verursacht auf **Normal 120 Schaden gegen Spieler**, vor Schutz durch Pilze. Ohne Lebens-Upgrades ist ein direkter Treffer tödlich. Gegen Barrikaden und Türen sind es **230**, gegen Geschütztürme **240** und gegen die Hütte **440 Basisschaden**; Verstärkungen reduzieren den erlittenen Schaden weiterhin. Die Schwierigkeit skaliert diese Werte: Spieler erhalten auf Leicht 84, auf Schwer 156 und auf Albtraum 204 Schaden vor Schutz.

## Schreie und Bodenbeben

Titanen haben acht eigene Sounddateien: drei tiefe, raue Schreie, ein kurzes Angriffsbrüllen, einen Todesschrei, zwei schwere Schritte und einen Bodeneinschlag. Die Schreie schichten die vorhandenen Zombieaufnahmen mit tiefen Kehlkopfresonanzen und Atemgeräuschen. Beim Auftauchen und beim Übergang unter 40 % Leben brüllen sie besonders deutlich. Im Anmarsch folgen weitere Schreie in Abständen von 20–30 Sekunden mit langen Ruhephasen dazwischen.

Schreie sind je nach Aktion bis etwa 230–260 m hörbar und kommen räumlich vom Kopf des Titanen. Beim Brüllen tritt die Musik kurz zurück. Schritte haben eine geringere Reichweite; Entfernung dämpft Höhen und Lautstärke. Ein eigener Kompressor und Limiter begrenzen den Mix, wenn mehrere Titanen gleichzeitig auftreten.

Schritte, Aufstampfen und der fallende Körper lösen kurze, weich abklingende Bodenerschütterungen aus. Die Stärke nimmt mit der Entfernung ab. Beim Tod fällt der schwere Körper erst nach dem Schrei zu Boden. Es gibt kein dauerhaftes Kamerawackeln. Unter **Einstellungen → Titanen-Bodenbeben** lässt sich die Stärke reduzieren oder ganz ausschalten; die Lautstärke folgt dem normalen Lautstärkeregler.

Der Host sendet diese Ereignisse auch im Koop an alle Mitspieler. Jeder hört die Quelle aus seiner eigenen Position und bekommt ein entsprechend starkes Beben. Bereits vergangene Schreie oder Schläge werden beim späteren Beitreten nicht nachgeholt.

## Koop und Prüfung

Der Host prüft Bauplätze, Ausrichtung, Punkte, Händlerentfernung, Reparaturen, Schaden und Bossangriffe. Türme, Upgrades, Bossleben, Warnflächen und Einschläge werden synchronisiert; spätes Beitreten übernimmt den aktuellen Zustand. Im Koop läuft die Welt während der Händlergespräche weiter; solo pausiert das Gespräch. Platzieren und Drehen bleiben Aktionen in der laufenden Welt.

Alle Spieler benötigen denselben neuen Build. Der Versionsabgleich lehnt alte Koop-Versionen ab.

Prüfungen:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode Defence
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode TitanHorror
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode TitanMix
powershell -ExecutionPolicy Bypass -File tools/test_multiplayer.ps1
```

Die Spieltests prüfen unter anderem tatsächliche Barrikadenangriffe, Turmtreffer und Deckung, Baukosten, Ausbaustufen, Bosswarnung/Ausweichen/Tod sowie den realen Weg vom Feld zum Zugang. Der Koop-Test startet vier eigenständige Godot-Prozesse. Bildschirmaufnahmen von Türmen, Bauvorschau und Titanen liegen unter `artifacts/defence/`.
