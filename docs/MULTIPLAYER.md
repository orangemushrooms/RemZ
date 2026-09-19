# RemZ: Koop über Hamachi oder LAN

Bis zu **vier Spieler insgesamt**: ein Host und drei Mitspieler. Jeder benötigt denselben aktuellen Ordner `builds/windows` mit `RemZ.exe` und `RemZ.pck`. Der Host spielt selbst mit; ein separater Server ist nicht erforderlich.

## Gemeinsam starten

1. Hamachi auf allen PCs starten und demselben Hamachi-Netzwerk beitreten. Alle Teilnehmer müssen darin online erreichbar sein.
2. Auf jedem PC `RemZ.exe` starten und im Hauptmenü **Mehrspieler / Hamachi** öffnen. Einen Namen eingeben.
3. Der Host klickt **Spiel erstellen**. Standardport: **UDP 24567**. Seine Hamachi-IPv4-Adresse steht in Hamachi; installierte IPv4-Adressen zeigt auch das Spiel an.
4. Die Mitspieler geben diese Adresse unter **Host-IP** ein, verwenden denselben Port und klicken **Beitreten**.
5. Sobald die Spieler in der Liste bereit sind, klickt der Host **Koop starten**. Die Schwierigkeit bestimmt der Host vor Rundenbeginn.

Im normalen LAN funktioniert die lokale IPv4-Adresse des Hosts. Hamachi muss dann nicht benutzt werden. Hamachi verbindet die PCs zu einem virtuellen Netzwerk; für die Spielverbindung darin ist keine zusätzliche Portweiterleitung am Router erforderlich. [Hamachi-Funktionsübersicht](https://vpn.net/).

## Firewall und Verbindung

`RemZ.exe` muss in der Windows-Firewall auf dem vom Hamachi-Adapter verwendeten Netzwerkprofil zugelassen sein. Bei einer eigenen Portregel ist **eingehend UDP 24567** auf dem Host freizugeben; bei geändertem Spielport entsprechend diesen Port verwenden. Die Firewall bleibt eingeschaltet.

Bei Verbindungsproblemen zuerst Hamachis Online-Status, die Host-IP, den Port und die Firewallfreigabe prüfen. Der Host muss bereits ein Spiel erstellt haben. Ein voller Server nimmt keinen fünften Spieler auf. Unterschiedliche Karten oder Netzwerkversionen werden abgewiesen; dann denselben Build auf alle PCs kopieren.

## Spielregeln

- Gemeinsame Wellen, Gegner, Uhrzeit, Türen, Schlüssel, Fenster und Barrikaden. Die Gegnerzahl wächst mit der Spielerzahl.
- Jeder besitzt eigene Lebenspunkte, Punkte, Waffen, Munition, Granaten, Verbesserungen und Pilze. Ein Weltgegenstand kann nur einmal aufgehoben werden. Schlüssel gelten für das ganze Team.
- Mitspieler sind sichtbar, tragen ihre aktuelle Waffe und erscheinen auf der Minimap. Namen und Lebenspunkte werden angezeigt. Schüsse und Schritte anderer Spieler sind räumlich hörbar.
- Kein Schaden durch Beschuss von Mitspielern. Eigene Granaten können den Werfer weiterhin verletzen.
- Bei 0 Lebenspunkten bleibt der Spieler am Boden. Ein lebender Mitspieler drückt in der Nähe **E** und bleibt drei Sekunden innerhalb von 2,5 Metern mit freier Sicht. Entfernen oder Sterben bricht die Wiederbelebung ab. Sie stellt 50 Lebenspunkte her.
- Nach einer überstandenen Welle kehren auch ausgeschiedene Spieler zurück. Erst wenn das ganze Team ausgeschieden ist, endet die Runde. Der Host kann eine neue Runde starten; die Gruppe bleibt verbunden.
- **Esc, Tab, B und V halten im Koop die Welt nicht an.** Der Spieler bleibt während der Menübedienung angreifbar.
- Freie Plätze können während der Runde belegt werden. Nach einer getrennten Verbindung ist erneutes Beitreten möglich; der persönliche Vorrat beginnt dabei neu, der gemeinsame Weltzustand bleibt erhalten.
- Verlässt der Host die Sitzung, kehren die Mitspieler mit einer Meldung ins Hauptmenü zurück. Es gibt keine automatische Hostübernahme oder Speicherung einer laufenden Koop-Runde.

## Startparameter für Verknüpfungen

```text
RemZ.exe -- --host --name=Michael --port=24567
RemZ.exe -- --join=25.12.34.56 --name=Luca --port=24567
```

Optional startet `--coop-auto-start=4` auf dem Host automatisch, sobald vier Spieler bereit sind. Ohne diese Option startet der Host über das Menü.

## Entwicklung und Prüfung

Die ENet-Verbindung läuft über UDP; siehe [Godots ENet-Dokumentation](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html). Der Host entscheidet über Treffer, Schaden, Nachladen, Käufe, Gegenstände und den gemeinsamen Spielzustand. Bewegung wird lokal dargestellt und vom Host gegen Reichweite und Kollision geprüft. Momentaufnahmen werden komprimiert und in kleine Pakete aufgeteilt; alte, unvollständige und doppelte Momentaufnahmen werden verworfen. Befehle benutzen einen zuverlässigen Kanal mit Sitzungs- und Sequenzprüfung.

```powershell
powershell -ExecutionPolicy Bypass -File tools/test_multiplayer.ps1
```

Der Test startet vier echte Godot-Prozesse über localhost mit separaten ENet-Verbindungen und prüft Lobby, Bewegung, Kampf, Käufe, gemeinsam beanspruchte Beute, Schlüssel, Türen, Barrikaden, Wiederbelebung, Granaten, eine volle Horde, Spielerlimit, Wiedereinstieg, Neustart und Hostende. Protokolle liegen in `artifacts/multiplayer`. Die Dateien zur Testkoordination ersetzen keine Netzwerkverbindung; Spielbefehle und Zustände laufen über ENet.

Weitere Tests starten nach Initialisierung der Autoloads, zum Beispiel:

```powershell
& 'C:/Users/miche/Desktop/Godot.exe' --headless --path godot --script res://tests/run.gd -- --suite=network_packets --smoke-test
& 'C:/Users/miche/Desktop/Godot.exe' --headless --path godot --script res://tests/run.gd -- --suite=smoke --smoke-test
```

Lokale Mehrprozess-Tests prüfen die Spielintegration. Eine Verbindung zwischen mehreren physischen PCs über Hamachi muss zusätzlich im tatsächlichen Netzwerk geprüft werden.
