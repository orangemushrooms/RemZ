# RemZ: Online-Lobby über Epic Online Services (EOS)

Seit dem 25. September 2026 hat das Mehrspieler-Menü zwei Wege:

| Weg | Transport | Wofür |
|---|---|---|
| **Online lobby** (Beitrittscode) | EOS Lobby + EOS P2P (`EOSGMultiplayerPeer`), direkt oder über Epics Relay | Internet, ohne Hamachi, ohne Portfreigabe, kein Epic-Konto |
| **Direct / LAN / Hamachi** | ENet über UDP 24567 (`ENetMultiplayerPeer`) | LAN, Hamachi, direkte IP (unverändert) |

Beide enden im selben Spielprotokoll: alle RPCs, Kanäle, Spieler-IDs (Host = 1), die Host-Autorität, das Lobby-
Handshake (`_hello` / `_welcome` / `_lobby` / `_begin`), Snapshots, späterer Beitritt, Wiedereinstieg und Neustart
sind transportunabhängig. `NetSession.transport` sagt, welcher Peer gerade trägt (`"enet"`, `"eos"`, `"offline"`).

## Bausteine

- `godot/addons/epic-online-services-godot/` - **EOSG 2.3.1** (3ddelano, MIT, 15. Sep 2026, EOS SDK 1.19.1.2),
  das Windows-Release des GitHub-Repos ohne die 11 MB `.pdb`. Enthält `EOSSDK-Win64-Shipping.dll`,
  `libeosg.windows.template_{debug.dev,release}.x86_64.dll`, `xaudio2_9redist.dll`, den Wrapper `eos.gd`
  (`EOS.*` Optionsklassen und Enums), die High-Level-Skripte `heos/*.gd` und `runtime.gd`. Der Editor-Plugin-Teil
  (`plugin.gd`) ist **nicht** aktiviert; die Autoloads `EOSGRuntime`, `HPlatform`, `HAuth`, `HLobbies`, `HP2P`
  stehen von Hand in `project.godot`. Lokale Änderung am Addon: die innere Klasse `EOS.Achievements` heisst hier
  `EOS.AchievementsApi` (`heos/hachievements.gd`, `heos/hachievement_data.gd` angepasst), weil RemZ eine globale
  Klasse `Achievements` hat und GDScript diese Überdeckung als Parse-Fehler ablehnt. Beim Aktualisieren des
  Addons diese Umbenennung wiederholen (`grep -rn "Achievements\." godot/addons/epic-online-services-godot`).
- `godot/scripts/online_lobby.gd` - Autoload **`Online`**. Startet die Plattform einmal (`HPlatform.setup_eos_async`,
  Overlay aus, Relay erlaubt, P2P-Warteschlangen 8 MB), meldet den Spieler mit **Connect Device ID** an (anonym,
  ohne Epic-Konto; `EOS_Connect_CreateDeviceId` + Login, bei `InvalidUser` `CreateUser`), erstellt bzw. findet
  die Lobby und baut den `EOSGMultiplayerPeer`. Alles EOS wird **dynamisch** angesprochen (`Engine.get_singleton
  ("IEOS")`, `ClassDB.instantiate("EOSGMultiplayerPeer")`, `load(".../eos.gd")`): lädt die Extension nicht (fehlende
  DLL, andere Plattform), ist nur die Online-Lobby aus (`Online.available()` false, Grund in
  `unavailable_reason()`); ENet läuft unverändert. Jede EOS-Rundreise wartet höchstens `STEP_TIMEOUT` 20 s.
- Lobby: Bucket `remz-coop-1`, `PublicAdvertised`, 4 Plätze, ohne Presence / RTC / Einladungen / Host-Migration.
  Attribute (öffentlich): `CODE` (6 Zeichen aus `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, ohne 0/O/1/I), `VERSION`
  (`Online.version_tag()` = `PROTOCOL|BUILD|Fingerprint[0:12]`), `HOST` (Name). Der Client sucht per Attribut
  (`bucket` + `CODE`), wiederholt eine leere Antwort bis zu dreimal im Abstand von 1,5 s (der Suchindex hinkt
  einer frischen Lobby nach), weist eine andere `VERSION` mit eigener Meldung ab, ebenso eine volle Lobby, und
  tritt sonst bei. P2P-Verbindungsanfragen nimmt der Host nur von Lobby-Mitgliedern an (`_review_requests`,
  15 s Gnadenfrist für einen noch nicht sichtbaren Beitritt).
- `godot/scripts/net_session.gd`: `host_online(name)` / `join_online(code, name)` (asynchron, geben `Error`
  zurück, melden jeden Schritt in `status`), `_activate_host` / `_activate_client` für beide Peers, `online_pending`
  (Abbrechen während Anmeldung / Suche über "Cancel" = `leave()`), `join_code`, Anwendungs-Ping `_ping` / `_pong`
  für jeden Peer ohne ENet-Statistik (`peer_ping`), Leaderboard-Zeilen einzeln (vier Zeilen mit langen Namen
  passten nicht in ein EOS-Paket), transportabhängige Fehlertexte. Kommandozeile: `--host-online`,
  `--join-code=XXXXXX` (neben `--host`, `--join=`), Test-Flags `--eos-fresh-device` (zweite Geräte-Identität),
  `--eos-cache=<name>` (eigener SDK-Cache je Prozess), `--eos-unavailable` (Laufzeit als fehlend behandeln),
  `--eos-check` (siehe unten).
- `godot/scripts/coop_menu.gd`: TabBar "Online lobby" / "Direct / LAN / Hamachi", Name, Beitrittscode-Feld,
  "Create lobby" / "Join with code", grosser Code mit "Copy code" für den Host, darunter die bisherige Spielerliste
  mit "Start co-op" / "Leave session" (während der Anmeldung "Cancel"). Der Modus wird in `user://network.cfg`
  gemerkt. Der Reiter heisst jetzt "Multiplayer".
- Paketgrenze: EOS P2P trägt höchstens **1170 Byte** je Paket, der EOSG-Header nimmt 6. `SNAPSHOT_CHUNK` 900 lässt
  Platz; `--suite=online_lobby` misst jede RPC-Form über einen Aufzeichnungs-Peer (grösstes Paket 957 Byte) und
  schlägt fehl, sobald eine über 1164 Byte geht. Unterstützte Modi: reliable -> ReliableOrdered, unreliable ->
  UnreliableUnordered, unreliable_ordered -> ReliableOrdered (EOS kennt kein unreliable-ordered).
- **Beenden:** Godot kehrt aus `quit()` nicht zurück, solange die erzeugte EOS-Plattform lebt (die SDK-Threads
  halten den Prozess). `Online._exit_tree()` schliesst deshalb den EOS-Peer, gibt die Lobby frei, tickt kurz und
  ruft `EOS_Platform_Release` + `EOS_Shutdown`. `--suite=eos_exit_probe --probe=lobby` prüft, dass der Prozess
  danach endet (ohne den Handler hing er in jeder Sonde ausser `--probe=release`).

## Zugangsdaten und Build

Die Client-Zugangsdaten (Product ID, Sandbox ID, Deployment ID, Client ID, Client Secret des Clients
"RemZ Windows", Policy **Peer2Peer**) liegen **nur** in der gitignorierten `.env` im Repository-Stamm:

```text
EOS_PRODUCT_NAME=RemZ
EOS_PRODUCT_ID=...
EOS_SANDBOX_ID=...
EOS_DEPLOYMENT_ID=...
EOS_CLIENT_ID=...
EOS_CLIENT_SECRET=...
```

- `python tools/eos_config.py` schreibt daraus `godot/eos.cfg` (ebenfalls gitignoriert; `--check` zeigt nur, ob
  jeder Wert vorhanden ist, Werte werden nie ausgegeben). Das Spiel liest `res://eos.cfg`; im Editor genügt auch
  die `.env` direkt, Umgebungsvariablen `EOS_*` füllen Lücken (CI).
- Das Export-Preset packt `eos.cfg` in `RemZ.pck` (`include_filter`), Spieler brauchen keine `.env`. Ein Client
  Secret einer Peer2Peer-Policy ist laut Epic dafür gedacht, im Spielclient zu stecken; es gehört trotzdem nie in
  Git, Logs oder Screenshots (`online_live` prüft, dass es nicht in `logs/coop-*.log` auftaucht).
- `tools/check-game.ps1 -Mode ExportWindows` ruft `eos_config.py` vor dem Export (bricht ohne vollständige `.env`
  ab) und prüft danach, dass `libeosg.windows.template_release.x86_64.dll`, `EOSSDK-Win64-Shipping.dll` und
  `xaudio2_9redist.dll` neben `RemZ.exe` liegen - Godot kopiert sie aus `[dependencies]` der `.gdextension`.
  Der Build-Ordner braucht diese drei DLLs zusätzlich zu `RemZ.exe` / `RemZ.pck`; itch.io-Zip = ganzer Ordner.
- Portal: Produkt **RemZ**, Client **RemZ Windows** mit Policy **Peer2Peer** genügt. Der Device-ID-Login
  brauchte **keine** weitere Portaleinstellung (Live-Test 25. Sep 2026: `EOS_LOGIN_OK` mit `CreateUser` beim
  ersten Gerät). Die Sandbox ist "Live"; ein neues Client Secret erfordert nur eine neue `.env` + Export.

## Prüfen

| Befehl | Was |
|---|---|
| `--suite=online_lobby --smoke-test --no-intro --no-music --no-foliage` (headless, 43 Checks, ohne Netz) | Codes, `.env`-Parsing, Trennung der Transporte (Online aus -> ENet unberührt, Abbruch, Ping), RPC-Paketgrössen, Menü |
| `--suite=online_live --smoke-test --no-intro --no-music --no-foliage` (headless, Internet, 21 Checks) | echtes EOS: Plattform, Device-ID-Login, Lobby mit Code, Suche (auch falscher Code, fremde Version), Hosten über den EOS-Peer, Verlassen, Lobby danach weg, sauberer Fehlschlag beim Beitritt |
| `powershell -ExecutionPolicy Bypass -File tools/test_online_coop.ps1` | zwei Godot-Prozesse auf diesem PC über das echte EOS-Backend (Client mit `--eos-fresh-device`): Beitritt per Code, Rundenstart, Snapshots, Bewegung, Ping, Verlassen |
| `tools/test_online_coop.ps1 -Packed` | dasselbe mit `builds/windows/RemZ.exe` über `--host-online` / `--join-code`; liest den Code und `ROUND_RUNNING players=2` aus den pro Zeile geschriebenen `builds/windows/logs/coop-<pid>.log` (Godots `--log-file` puffert bis zum Ende) |
| `builds/windows/RemZ.exe --headless -- --eos-check --smoke-test --no-foliage --no-music` | gepackter Build: `EOS_CHECK runtime= credentials= login= nat_type= lobby= search=` und `EOS_CHECK_DONE ok=true` |
| `--suite=eos_exit_probe --probe=lobby` | der Prozess endet nach `quit()` trotz gelaufener Plattform |

Die bestehenden ENet-Suiten (`tools/test_multiplayer.ps1`, `test_packed_coop.ps1`, `connection_cancel`,
`network_packets`, `menu_flow`, `leaderboard`) decken den Direktweg weiter ab; `language` (en/de) fegt das neue Menü.

## Grenzen und Hinweise

- Die Lobby ist öffentlich suchbar (nur so funktioniert die Codesuche); der Code ist Bequemlichkeit, kein Schutz -
  wie bisher die IP. Der Host nimmt am P2P-Socket nur Lobby-Mitglieder an.
- Ein Device-ID-Konto hängt am Windows-Benutzer (Keychain); jeder Windows-Benutzer ist ein eigener EOS-Spieler.
  Zwei Instanzen auf einem PC teilen sich die Identität, ausser die zweite startet mit `--eos-fresh-device`.
- Keine Host-Migration: verlässt der Host, ist die Lobby zu und die Mitspieler landen mit Meldung im Hauptmenü
  (wie bei ENet).
- Wenn EOS ausfällt oder die DLLs fehlen, bleibt "Direct / LAN / Hamachi" vollständig nutzbar; das Menü zeigt
  den Grund im Online-Reiter.
