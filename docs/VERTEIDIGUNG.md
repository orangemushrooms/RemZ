# Verteidigung und Feldtitanen

**V** öffnet die Planung der vier Barrikadenlinien. **E** öffnet sie in der Nähe. Eine ganze Linie kostet 50 Punkte, Reparatur 25. Drei Stufen mit 150 / 300 / 450 Strukturpunkten; Verstärkungen reduzieren zusätzlich erlittenen Schaden.

Zombies greifen eine gebaute Linie an, wenn sie ihren Weg zur Hütte versperrt. Sie behalten das Durchbruchsziel beim seitlichen Ausweichen. Gegner aus den vier Anmarschrichtungen berücksichtigen den zugehörigen befestigten Zugang. Nach dessen Zerstörung setzen sie die Verfolgung fort. Eine Linie schützt ihren Zugang; bereits dahinter befindliche Gegner bleiben gefährlich.

## Automatische Geschütztürme

- **T** aktiviert die Bauvorschau. Auf einen freien Bodenplatz schauen, mit **E** bauen; **T / Esc** bricht ab. Grün bedeutet gültig, Rot zeigt den Grund für eine Ablehnung.
- Baukosten: **120 Punkte**. Höchstens **6 Türme insgesamt**, auch im Koop. Bauplatz höchstens 8 m entfernt, mit freier Sicht, genug Platz und ausreichend ebenem Boden.
- Beim Turm öffnet **E** die Verwaltung: Ausbauen, Reparieren oder Abbauen.
- Ausbaustufen: 240 / 400 / 600 Struktur, 26 / 32 / 38 m Reichweite. Ausbauten kosten 100 und 175 Punkte. Reparatur kostet 35 Punkte und stellt die volle Struktur wieder her. Nur der Erbauer kann abbauen und erhält 40 Punkte zurück.
- Türme schwenken zu sichtbaren Gegnern, feuern mit Streuung und legen bei Überhitzung eine Kühlpause ein. Munition wird automatisch versorgt. Wände und Gelände stoppen Schüsse; Teammitglieder nehmen keinen Turmschaden.
- Zombies und Titanen können die Türme zerstören. Hinter einer Barrikade sind sie deutlich besser geschützt. Turmabschüsse geben dem Erbauer Punkte. Verlässt dieser die Sitzung, übernimmt der Host seine Türme.
- Auf der Minikarte erscheinen Türme als blaue Quadrate.

## Feldtitanen

Der erste rund **27 m grosse Titan erscheint in Welle 6**, danach alle drei Wellen. Ab Welle 12 erscheinen in diesen Wellen zwei Titanen, ab Welle 24 höchstens drei, jeweils an getrennten Feldpositionen. Die bisherigen Brockenwellen bleiben erhalten. Titanen kommen über die offenen südlichen Felder, mit eigenem geriggtem Modell, schweren Schritten und Bosslebensanzeige.

Vor dem Flächenangriff erscheint eine orange Markierung, die dem Gelände folgt. Sie bleibt am angekündigten Einschlagort; innerhalb der 2,4 Sekunden Vorwarnzeit kann man herauslaufen. Der Einschlag beschädigt Spieler und Verteidigungen im Radius von 8,5 m, gefolgt von einer Erholungsphase. Wände begrenzen den Einschlag und schützen vor der Druckwelle. Unter 40 % Leben wird der Titan schneller. Kugeln und Nahkampfstösse können ihn nicht dauerhaft betäuben. Schwierigkeit, spätere Wellen und Spielerzahl beeinflussen seine Stärke.

## Koop und Prüfung

## Schreie und Bodenbeben

Titanen haben acht eigene Sounddateien: drei tiefe, raue Schreie, ein kurzes Angriffsbrüllen, einen Todesschrei, zwei schwere Schritte und einen Bodeneinschlag. Die Schreie schichten die vorhandenen Zombieaufnahmen mit tiefen Kehlkopfresonanzen und Atemgeräuschen. Beim Auftauchen und beim Übergang unter 40 % Leben brüllen sie besonders deutlich. Im Anmarsch liegen zwischen weiteren Schreien 20–30 Sekunden Ruhe.

Schreie sind je nach Aktion bis etwa 230–260 m hörbar und kommen räumlich vom Kopf des Titanen. Beim Brüllen tritt die Musik kurz zurück. Schritte haben eine geringere Reichweite; Entfernung dämpft Höhen und Lautstärke. Ein eigener Kompressor und Limiter begrenzen den Mix, wenn mehrere Titanen gleichzeitig auftreten.

Schritte, Aufstampfen und der fallende Körper lösen kurze, weich abklingende Bodenerschütterungen aus. Die Stärke nimmt mit der Entfernung ab. Beim Tod fällt der schwere Körper erst nach dem Schrei zu Boden. Es gibt kein dauerhaftes Kamerawackeln. Unter **Einstellungen → Titanen-Bodenbeben** lässt sich die Stärke reduzieren oder ganz ausschalten; die Lautstärke folgt dem normalen Lautstärkeregler.

Der Host sendet diese Ereignisse auch im Koop an alle Mitspieler. Jeder hört die Quelle aus seiner eigenen Position und bekommt ein entsprechend starkes Beben. Bereits vergangene Schreie oder Schläge werden beim späteren Beitreten nicht nachgeholt.

## Koop und Prüfung

Der Host prüft Bauplätze, Punkte, Reparaturen, Schaden und Bossangriffe. Türme, Upgrades, Bossleben, Warnflächen und Einschläge werden synchronisiert; spätes Beitreten übernimmt den aktuellen Zustand. Im Koop läuft die Welt während der Turmverwaltung weiter; solo pausiert das Spiel.

Alle Spieler benötigen denselben neuen Build. Der Versionsabgleich lehnt alte Koop-Versionen ab.

Prüfungen:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode Defence
powershell -ExecutionPolicy Bypass -File tools/test_multiplayer.ps1
```

Die Spieltests prüfen unter anderem tatsächliche Barrikadenangriffe, Turmtreffer und Deckung, Baukosten, Ausbaustufen, Bosswarnung/Ausweichen/Tod sowie den realen Weg vom Feld zum Zugang. Der Koop-Test startet vier eigenständige Godot-Prozesse. Bildschirmaufnahmen von Türmen, Bauvorschau und Titanen liegen unter `artifacts/defence/`.
