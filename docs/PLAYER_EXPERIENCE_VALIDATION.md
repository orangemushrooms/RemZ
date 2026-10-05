# Prüfbericht: Einstieg, Bedienung und Spielkomfort

Stand: **5. Oktober 2026**, Windows, **Godot 4.7.2 stable** (`ed1daf0bf`).
Zielkennung des aktuellen Quellstands: **Protokoll 8**,
`remz-dev-20261005-player-experience`, Menüversion **Co-op 2026.10.05-F**.

**Technische Abnahme abgeschlossen:** Die unten als bestanden aufgeführten Läufe sind
anhand ihrer Abschlussmarker und Fehlerprotokolle bestätigt. Auch der Windows-Export,
beide nativen Map-Starts und die Funktionsprüfung des tatsächlichen Pakets sind bestanden.
Die Uploadbestätigung wird separat im Quellrepository protokolliert.
Ein bestandenes Ergebnis der vorherigen
[Expedition-Veröffentlichung](EXPEDITION_VALIDATION.md) gilt nicht automatisch für
diesen Stand. [Bedienung und Spielregeln](EXPEDITIONS.md) beschreiben die Änderungen.

## Ausgangsprobleme und Änderungen

- **Überladener Einstieg:** Die permanente Feldbuch-/Klassenaktions-/Verbandsleiste
  und die pauschale Aufzählung von Menütasten entfallen. Beim Ankommen steht ein
  einzelner nächster Schritt im Vordergrund: der Vendor im Lager. Praktische
  Hinweise erscheinen nacheinander, an passenden Orten beziehungsweise in ruhigen
  Wellenpausen. Im Profil gemerkte Lektionen werden nicht ständig wiederholt.
- **Einführung beim Vendor:** Vier kurze Seiten behandeln Ausrüstung, die tatsächlich
  gewählte Klasse, das Feldbuch und den jeweiligen Kartenbau. Die Assassin-Erklärung
  nennt V und die Freischaltung; andere Klassen nennen Z mit ihrer eigenen Wirkung.
  Die Einführung ist freiwillig, wiederholbar und überspringbar. Das Lesen kauft
  nichts und vergibt keine mehrfachen Auftragsbelohnungen.
- **QWERTZ-Eingabe:** Z und K verwenden logische Buchstaben statt der US-Position auf
  der Tastatur. Z funktioniert auch bei gehaltenem Shift. Y, Ctrl+Z, Wiederholungs-
  ereignisse, Texteingaben und fremde Bedienmodi aktivieren die Fähigkeit nicht.
- **Feldbuch:** Fünf kurze Navigationsseiten, klare Karten, aufklappbare Details,
  vollständige angenommene Aufträge, erklärter Klassenstatus, kontextabhängige
  Aktionen und Schiessstandrekorde ersetzen die unstrukturierte Text-/Buttonliste.
  Die Oberfläche liegt modal über dem Spiel; Solo pausiert, Koop läuft weiter.
  Escape, K im Codefeld, Eingabefokus und die Rückkehr zum ursprünglichen Pausenmenü
  sind getrennt behandelt. Laden erhält eine Bestätigung. Rückmeldungen von
  Koop-Anfragen werden im geöffneten Feldbuch sichtbar gemacht.
- **Waffenanzeige:** Waffenname und Munition liegen kompakter am unteren rechten Rand.
  Leere Nachladeanzeigen bleiben verborgen. Die Geometrie wird gegen Schnellzugriff
  und Minimap geprüft; das mittlere Sichtfeld für die gehaltene Pistole bleibt frei.
- **Interaktionen:** Jede Map wählt dieselbe E-Aktion für Hinweis und Ausführung.
  Ein einzelner Tastendruck kann eine überlappende Expeditionskiste einsammeln,
  ohne gleichzeitig den Händler dahinter zu öffnen. Ein weiterer bewusster
  Tastendruck erreicht danach den Händler.
- **Menüs und Wellen:** Enter auf einer Schaltfläche wie «Weiter» beendet nur den
  Dialog beziehungsweise die Pause. Erst eine eigenständige Enter-Eingabe im Spiel
  verkürzt die Wellenpause. Planes-Baukits öffnen keine zweite Oberfläche hinter
  Inventar oder Pause; Abbrechen eines inaktiven Werkzeugs aktiviert den Spieler
  nicht versehentlich. Solo-Pausen halten Spielzeit, Killserie und Spielsysteme an.
- **Spielstände und Vorräte:** Ein früherer Spielstand bleibt nach später angenommenen
  Aufträgen, neuen Vorräten und Relikten gültig. Laden stellt diese Zustände sowie
  Position und Bewegung konsistent zurück. Planes-Sammelobjekte, Pflanzen und
  Schiessstandbeute werden mit zurückgesetzt. Namenszuordnung nach erneutem Beitritt
  erhält auch Händler- und seltene Inventare. Das Sanitäteraugment überschreitet
  die Grenze von acht Verbänden nicht.

## Bestätigte gezielte Prüfungen

Die Zahlen beziehen sich auf einzelne Läufe. Tests überschneiden sich in Maps und
Bedienwegen; sie werden deshalb nicht zu einer vermeintlichen Gesamtzahl unterschiedlicher
Spielmechaniken addiert. Der spätere englische Feldbuchlauf enthält zusätzliche
Fokusprüfungen; der deutsche Renderlauf enthält zusätzlich Bildspeicherprüfungen.

| Prüfung | Umfang | Bestätigtes Ergebnis | Protokoll unter `artifacts/expansion-tests/` |
| --- | --- | --- | --- |
| Kompilierung nach Abschluss der Produktionsänderungen | 381 Spiel- und Testskripte | 0 defekte Skripte | `compile_all-en-usability-final.log` |
| Eingaben, HUD und reale Pausenmenüs, Deutsch gerendert | Forest und Planes, 106 Assertions | 106 bestanden | `player_experience-de-render-final.log` |
| Feldbuch, aktueller englischer Funktionslauf | Beide Maps, 133 Assertions | 133 bestanden | `fieldbook_usability-en-final.log` |
| Feldbuch, deutscher Renderlauf | Beide Maps, 151 Assertions und 22 Bilder | 151 bestanden | `fieldbook_usability-de-render-refined.log` |
| Schrittweise Einführung, Forest | 29 Assertions | 29 bestanden | `onboarding_polish-en-forest.log` |
| Schrittweise Einführung, Planes | 31 Assertions | 31 bestanden | `onboarding_polish-en-planes.log` |
| Vendor-Einführung, Deutsch | 11 Assertions | 11 bestanden | `vendor_tutorial-de-onboarding.log` |
| Vendor-Einführung, Deutsch gerendert | 13 Assertions, 720p-Lesbarkeit | 13 bestanden | `vendor_tutorial-de-render-onboarding.log` |
| Bestehende Planes-Aufträge | 21 Assertions | 21 bestanden | `planes_quests-en-onboarding.log` |
| Gezielter Gameplay-Audit, Forest | 22 Assertions | 22 bestanden | `gameplay_ux_audit-en-forest-final.log` |
| Gezielter Gameplay-Audit, Planes | 35 Assertions | 35 bestanden | `gameplay_ux_audit-en-planes-final.log` |
| Spielstand-Datenformen und Netzwerk-ID-Zuordnung | 13 Assertions | 13 bestanden | `checkpoint_schema-en-usability.log` |
| Planes-Erkundung ohne Survival-Systeme | 33 Assertions | 33 bestanden | `planes-en-onboarding-exploration.log` |
| Erweiterte Expeditionssuite | Beide Maps, 442 Assertions | 442 bestanden | `expedition-en-usability.log` |
| Zusätzliche Bestandsprüfungen | 11 Suiten, 272 Assertions | 11/11 bestanden | `usability-regressions.json` |
| Breite Bestandsregressionen | 34 Suiten, 3001 Assertions | 34/34 bestanden | `regressions.json` |
| Echter Forest-Koop | Zwei ENet-Prozesse, Host 24 / Client 10 Assertions | 34 bestanden | `coop-forest/host.log`, `coop-forest/client.log` |
| Echter Planes-Koop | Zwei ENet-Prozesse, Host 28 / Client 13 Assertions | 41 bestanden | `coop-planes/host.log`, `coop-planes/client.log` |
| Netzwerk-Kompatibilität | Drei echte ENet-Prozesspaare, 36 Assertions | 36 bestanden | `network-compatibility.json` |
| Offline-Lobby | 44 Assertions | 44 bestanden | `online_lobby-en-usability-final.log` |
| Spielstand nach Prozessneustart | Forest 1+7, Planes 1+5 Assertions | 14 bestanden | `restarts.json` |
| Tatsächliches Windows-Paket | Beide nativen EXE-Starts; PCK Forest 16 / Planes 16 Assertions | 32 bestanden | `packed.json` |

Der abschliessende HUD-/Eingabelauf prüft zusätzlich M während Gameplay, Feldbuch
und Pause sowie die echten Pausenmenüs beider Maps bei 900p und 720p. Die
Schnellzugriffsleiste bleibt in der Pause verborgen. Die Feldbuchbilder entstanden
vor der letzten Wortkorrektur des Erstkontakts von Mara zu Vendor sowie den letzten
Fokusverbesserungen; diese Änderungen sind im nachfolgenden englischen Funktionslauf
enthalten. Das gezeigte Layout entspricht bereits der überarbeiteten Darstellung.

## Prüfmethoden und Bildkontrolle

Die Suiten laden die tatsächlichen Forest- und Planes-Szenen mit eigenen Testprofilen
und isoliertem `APPDATA`. Tests setzen einzelne Ausgangszustände gezielt, stoppen
unnötige Wellen-/Spielerbewegung und speisen echte Tastaturereignisse in Godots
Eingabeverarbeitung ein. QWERTZ wird durch logisches Z mit physischer Y-Position
geprüft; die umgekehrte Kombination muss ohne Klassenaktion bleiben. QWERTY, Shift,
Ctrl, Echo sowie sichtbarer GUI-Fokus sind eigene Fälle.

Der Feldbuchtest prüft tatsächliche Mindestgrössen, Sichtrechtecke und horizontalen
Überlauf aller fünf Seiten auf 720p- und 1080p-Zeichenflächen. Er prüft zusätzlich
ausreichend Inhaltshöhe unter dem Kopfbereich, Enter auf der fokussierten Navigation,
K als Texteingabe, Escape, Pause-Rückkehr, Fokus, Zustand nach Niedergehen,
Augmentauswahl und kontextabhängige Planes-Aktionen. Das Löschen trifft ein echtes
brennendes Weizenfeld; die Augmentauswahl verwendet den tatsächlichen Transaktionspfad.

Die gerenderten Aufnahmen wurden nach Ende der Ladeblende angefertigt. Überblick,
Team, Entdeckungen, Expedition und Augmentangebote wurden anhand der Bilder auf
Lesbarkeit und sichtbare Überlagerungen kontrolliert. Dabei wurde ein echter Fehler
im umgebrochenen Zurück-Button gefunden und vor dem bestandenen Renderlauf behoben.
Die Prüfung beschränkt sich somit nicht auf die Aussenkante des Fensters.

- Feldbuchbilder: `artifacts/fieldbook-polish/{forest|planes}-page-{0..4}-{720|1080}-de.png`.
- Augmentangebote: `artifacts/fieldbook-polish/{forest|planes}-augment-offers-de.png`.
- Vendor-Einführung: `logs/vendor-tutorial.png`.
- Gemeinsame HUD-/Pausenbilder: `artifacts/player-experience/`; Forest und Planes
  bei 900p und 720p wurden auf freie Waffensicht, Abstände und Lesbarkeit geprüft.

Der Gameplay-Audit überschneidet absichtlich eine echte Vendor-Interaktionszone mit
einer Expeditionskiste und prüft Geldänderung sowie Menüstatus nach einem echten E.
Er speichert einen ruhigen Durchlauf, führt anschliessend normale Erwerbs- und
Auftragsaktionen aus und lädt den älteren Zustand wieder. Die Planes-Pausenprüfung
lässt unter anderem Missions-, Wetter-, Sonnen-, Wellen-, Brand- und Klassenbuff-
Timer laufen und prüft, dass sie während der Solo-Baukitauswahl unverändert bleiben.

## Freigabe

Die Paketprüfung startet zuerst die exportierte EXE bis zur spielbereiten Map.
Danach lädt der zur Engine passende Skriptrunner genau diese PCK und prüft zusätzlich
QWERTZ-Z, Waffenpanel, Feldbuchknopf, Pausenrückkehr, M-Sperre sowie echte Spielstände.
Entwicklungssuiten liegen ausserhalb des veröffentlichten Pakets.

| Prüfung | Status |
| --- | --- |
| Gemeinsame HUD-/Pausen-/Eingabesuite und Renderbilder | 106/106 bestanden |
| Vollständige Kompilierung nach Abschluss aller Produktionsänderungen | 381 Skripte, 0 Fehler |
| Breite bestehende Regressionen und erweiterte Expeditionssuite | 34/34 Suiten (3001 Assertions) und 442/442 Expeditionsprüfungen bestanden |
| Neue Kennung: Protokoll-/Fingerprint-Handshakes und Offline-Lobby | 36 + 44 Assertions bestanden |
| Vollständige reale Zwei-Prozess-Koop-Prüfung auf Forest und Planes | Forest 24+10 und Planes 28+13 Assertions bestanden |
| Spielstandprüfung mit getrennten Schreib- und Neustartprozessen | 14 Assertions bestanden |
| Deutscher Katalog- und Platzhaltercheck | 2628 Einträge, 0 Probleme; deutscher Menütest 104/104 |
| Neuer Windows-Release-Export und EOS-Konfiguration | Export ohne Fehler; Runtime-Konfiguration geprüft |
| Start der tatsächlichen EXE und Funktionsprüfung der neu exportierten PCK | Beide Maps bereit; 16+16 Assertions bestanden |
| Dateiprüfsummen | `BUILD-INFO.json` im Windows-Download; vor dem Upload erneut geprüft |
| Veröffentlichungs- und Uploadnachweis dieses Builds | Separate Serverbestätigung in `logs/publish-itch-player-experience.out` im Quellrepository |

## Wiederholen

Aus dem Repository-Stamm; der Runner verwendet standardmässig
`C:/Users/miche/Desktop/Godot.exe`. Für einen anderen Engine-Pfad `GODOT` setzen.

```powershell
python -X utf8 tools/test_expansion.py compile_all
python -X utf8 tools/test_expansion.py player_experience --lang en
python -X utf8 tools/test_expansion.py player_experience --render --lang de
python -X utf8 tools/test_expansion.py fieldbook_usability --lang en
python -X utf8 tools/test_expansion.py fieldbook_usability --render --lang de
python -X utf8 tools/test_expansion.py onboarding_polish --lang en
python -X utf8 tools/test_expansion.py onboarding_polish --lang en --flag=--planes-onboarding
python -X utf8 tools/test_expansion.py vendor_tutorial --render --lang de
python -X utf8 tools/test_expansion.py gameplay_ux_audit --lang en
python -X utf8 tools/test_expansion.py gameplay_ux_audit --lang en --flag=--audit-planes
python -X utf8 tools/test_expansion.py planes_quests --lang en
python -X utf8 tools/i18n.py check --quiet
git diff --check
```

Die breit angelegten Abnahmen verwenden zusätzlich `tools/test_expansion_batch.py`,
`tools/test_expansion_coop.py`, `tools/test_network_compatibility.py`,
`tools/test_expansion_restart.py` und `tools/test_expansion_pack.py`. Letztere Suite
setzt den frisch exportierten Windows-Build voraus. Auf dem verwendeten Rechner
mit 16 GB RAM werden höchstens drei vollständige Map-Prozesse gleichzeitig gestartet;
gerenderte Tests werden untereinander zeitlich getrennt.

## Grenzen

Automatisierte Eingabe-, Zustands- und Geometrieprüfungen sowie gerenderte Bilder
belegen die aufgeführten Abläufe. Sie ersetzen keine längeren menschlichen
Spielrunden und garantieren weder Fehlerfreiheit in jeder Situation noch subjektiven
Spielspass. Vier echte gleichzeitig verbundene Clients, Internet-Koop über EOS/NAT,
andere Rechner und Langzeitbalance sind durch die gezielten lokalen Ergebnisse
dieses Prüfstands nicht nachgewiesen.

Die eingeschränkte Windows-Umgebung meldet den bereits im ursprünglichen Projekt
vorhandenen Fehler `Failed to read the root certificate store`. Ausschliesslich
diese bekannte Meldung ist im Runner ausgenommen. Andere Engine- und Skriptfehler,
fehlende Abschlussmarker, fehlgeschlagene Assertions und Zeitüberschreitungen machen
einen Lauf ungültig; der Runner beendet seinen eigenen Kindprozess bei Skriptfehlern.
