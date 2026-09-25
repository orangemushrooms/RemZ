# RemZ: Co-op over the online lobby, Hamachi or LAN

Up to **four players in total**: one host and three teammates. Everyone needs the same current `builds/windows` folder with `RemZ.exe`, `RemZ.pck` and the three DLLs next to them. The host plays along; no separate server is needed. **Multiplayer** in the main menu offers two ways in:

- **Online lobby** - over the internet, without Hamachi and without opening a port on the router. The host clicks **Create lobby** and gets a six-letter **join code** (for example `K7PZ4M`; **Copy code** copies it). Teammates type the code under **Join code** and click **Join with code**. The connection runs through Epic Online Services (peer to peer, automatically relayed through Epic when routers are strict); no Epic account is needed, the sign-in is anonymous with a device identity. The code is valid while the host stays in the lobby.
- **Direct / LAN / Hamachi** - the previous way with an IP address and UDP port, unchanged (described below).

Both ways end in the same player list; the host presses **Start co-op**. If the online service is down or its DLLs are missing, the online tab explains why and the direct way keeps working.

## Starting together (Direct / LAN / Hamachi)

1. Start Hamachi on all PCs and join the same Hamachi network. All participants must be online and reachable in it.
2. Start `RemZ.exe` on every PC and open **Multiplayer** in the main menu and pick **Direct / LAN / Hamachi**. Enter a name.
3. The host clicks **Host game**. Default port: **UDP 24567**. The host's Hamachi IPv4 address is shown in Hamachi; the game also displays the IPv4 addresses installed on the PC.
4. The teammates enter this address under **Host IP**, use the same port and click **Join**.
5. As soon as the players in the list are ready, the host clicks **Start co-op**. The host sets the difficulty before the round starts.

On a regular LAN, the host's local IPv4 address works. Hamachi is not needed then. Hamachi connects the PCs into a virtual network; the game connection inside it needs no extra port forwarding on the router. [Hamachi feature overview](https://vpn.net/).

## Firewall and connection

`RemZ.exe` must be allowed through Windows Firewall on the network profile the Hamachi adapter uses. If you use a port rule of your own, allow **inbound UDP 24567** on the host; if you changed the game port, use that port instead. Leave the firewall switched on.

If you run into connection problems, first check Hamachi's online status, the host IP, the port and the firewall rule. The host must already have created a game. A full server does not accept a fifth player. Different maps or network versions are rejected; in that case, copy the same build to all PCs.

## Rules

- A new session starts with the normal intro: the KONM logo, waking up in the fog and a shared start on the Sennhofstrasse. The direction arrow shows the way to the forest hut. As soon as one team member reaches the Hut Path, the first shared wave starts. Players who join later appear with the team; after a team wipe, the next round starts as in single player, without the intro.
- Waves, enemies, time of day, doors, keys, windows and barricades are shared. The number of enemies grows with the number of players.
- Everyone has their own health, Rem Dollars, weapons, ammo, grenades, upgrades, skins and quest rewards. An item in the world can only be picked up once. Keys and quest goals such as deliveries and titan kills count for the whole team.
- Weapons and training can only be bought from NPCs. The host re-checks location, line of sight, price and unlocks. Vendor stands at the campfire, Mechanic north of it; rare weapons are sold by the hidden Secret Vendor. [Traders, quests and prices](PROGRESSION.md).
- Teammates are visible, carry their current weapon and appear on the minimap. Names and health are displayed. Other players' shots and footsteps are heard in 3D space.
- No damage from shooting teammates. Your own grenades can still hurt you.
- At 0 health, a player stays down. A living teammate presses **E** nearby and stays within 2.5 meters with a clear view for three seconds. Moving away or dying cancels the revive. It restores 50 health.
- After a wave is survived, players who were down come back too. The round only ends once the whole team is down. The host can start a new round; the group stays connected.
- **In co-op, trader conversations, Esc and I do not pause the world.** You can still be attacked while you use a menu. Q toggles the quest tracker, V points you to defense advice at Mechanic.
- Free slots can be filled during the round. After a dropped connection you can join again; your personal supplies start over, the shared world state is kept.
- If the host leaves the session, the teammates return to the main menu with a message. There is no automatic host migration and no saving of a running co-op round.

## Launch options for shortcuts

```text
RemZ.exe -- --host --name=Michael --port=24567
RemZ.exe -- --join=25.12.34.56 --name=Luca --port=24567
RemZ.exe -- --host-online --name=Michael
RemZ.exe -- --join-code=K7PZ4M --name=Luca
```

An online host writes its code as `ONLINE_CODE=K7PZ4M` into the log (`logs/coop-*.log` next to the exe).

Optionally, `--coop-auto-start=4` on the host starts the round automatically as soon as four players are ready. Without this option, the host starts from the menu.

## Quick test with two windows on one PC

Run this in PowerShell in the project folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_local_coop.ps1
```

This opens two windows of the Windows build: `LocalHost` creates the game, `LocalClient` connects to `127.0.0.1` on port 24567. Once both have finished loading and are ready, press **Start co-op** in the host window. Switch between the windows with **Alt+Tab**. Hamachi is not needed for this test. If the host loads more slowly, press **Join** in the client again if necessary. Close any tests already running on the same port first, or append `-Port 24568` to the command.

Without the script: open `RemZ.exe` twice, host a game under **Multiplayer > Direct / LAN / Hamachi** in the first window, and join from the second one with host IP **127.0.0.1** and the same port. Only the host starts the round.

A short manual run-through:

1. Move both characters and have them shoot; each time, the character must react visibly in the other window.
2. Press **Esc** on the host, switch to the client and keep walking and shooting. Enemies and the clock must keep running. Then swap roles.
3. Repeat this with **I** (inventory), a trader conversation (**E** at the NPC) and the tower build menu (**T**). The player in the menu can still be attacked.
4. Pick up an item, build a barricade and kill an enemy: the world state must match in both windows.
5. Let one player die and revive them with the other; the round only ends when the whole team dies. Then restart as the host.
6. Leave with the client and join again. Finally, leave with the host: the client must return to the main menu.

Two rendered windows need considerably more graphics power than one. Lower the graphics quality if needed. The separate logs are in `artifacts/local-coop`.

## Development and testing

The lobby only reports a teammate as ready after their client has applied the start data and confirmed it. This data belongs to the new round in progress; no saved game is loaded. The first transfer is compressed and split into small reliable packets. Repeated ready requests do not cause multiple full transfers.

**Open logs** in the multiplayer menu opens the current diagnostics folder. From program start, the Windows build writes to `logs/coop-*.log` next to the EXE right away. If that folder is not writable, a user folder is used instead. Connection attempts, timeouts and cancellations before joining are logged too. The version line in the menu must match for both players.

A cancelled connection attempt keeps the map that is already loaded. ENet is disconnected outside its network callback. If the round had already started or the shared world state had been applied, the map is rebuilt for the main menu; a loading indicator appears while this happens. `godot/tests/connection_cancel.gd` checks repeated cancellations, timeouts, connection errors, hosting again and diagnostics output that can be read immediately.

Movement packets carry a sequence number that the host acknowledges in the world state. The client compares the host's position with its own position at that sequence number. Later local movement is kept; a delayed acknowledgement alone does not trigger a reset. Real deviations caused by collisions or rejected movement are still corrected. The host also checks the player capsule while it slides along the ground and walls.

The online lobby release uses network protocol 3 (application ping, leaderboard rows sent one by one). Host and teammates have to switch to the new release together. `godot/tests/movement_sync.gd` checks delayed acknowledgements (100–1,000 ms), missing and outdated updates, real position corrections, and ground and wall collisions.

The ENet connection runs over UDP; see [Godot's ENet documentation](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html). The host decides on hits, damage, reloading, purchases, items and the shared game state. Movement is shown locally and checked by the host against range and collision. Snapshots are compressed and split into small packets; old, incomplete and duplicate snapshots are discarded. Commands use a reliable channel with session and sequence checks.

```powershell
powershell -ExecutionPolicy Bypass -File tools/test_multiplayer.ps1
powershell -ExecutionPolicy Bypass -File tools/test_packed_coop.ps1
```

The test starts four real Godot processes over localhost with separate ENet connections and checks the lobby, movement, combat, purchases, shared loot claims, keys, doors, barricades, revives, grenades, a full horde, the player limit, rejoining, restarting and the host leaving. Logs are in `artifacts/multiplayer`. The test coordination files do not replace a network connection; game commands and states go over ENet.

The second command also checks the exported Windows build with three EXE processes and a probe client. Logs are in `artifacts/defence`. The menu test opens the pause menu, inventory, trader and barricade menu on host and client, simulates a loss of focus and checks that movement, world time and network updates keep running. World state checks wait for a current snapshot, so slow loading is not mistaken for a sync error.

Further tests start after the autoloads have been initialized, for example:

```powershell
& 'C:/Users/miche/Desktop/Godot.exe' --headless --path godot --script res://tests/run.gd -- --suite=network_packets --smoke-test
& 'C:/Users/miche/Desktop/Godot.exe' --headless --path godot --script res://tests/run.gd -- --suite=smoke --smoke-test
```

Local multi-process tests check the game integration. A connection between several physical PCs over Hamachi also has to be tested on the actual network.

## Leaderboard

**Hold Tab** to see the leaderboard of the current round: Kills, Headshots, Deaths, Titan Kills, Assists, Rem Dollars and live Ping. **Q** toggles the quest tracker; the quick melee / rifle butt strike is on **H**. The leaderboard does not pause the game and is also available after you are down or at the end of the round.

The host counts separately for each player. The last hit gets the kill; the Headshots column counts fatal headshots. Titan Kills also count as normal kills. Every other player who damaged the enemy during its lifetime gets exactly one assist. Automatic towers count for their owner, manned towers for the gunner. Burn and explosion damage keep their source. A death counts when a player goes down, and again only after a revive; being saved by the Phoenix Ash talisman does not count as a death.

Sort order: Kills, Titan Kills, Headshots, Assists in descending order, then fewer Deaths. Players who join later get the standings so far; dropped connections stay listed, marked OFFLINE. A new round resets all five counters. This is a per-round leaderboard, separate from the saved solo high scores table.

Tests: `--suite=leaderboard --smoke-test --no-intro --no-music --no-foliage`; optionally `--render-leaderboard` for an image in `artifacts/leaderboard/`. `tools/test_multiplayer.ps1` checks the sync with three real clients, late joining, revives, the end of a round and restarting.

The **Rem Dollars** column shows the balance currently available (also after purchases), not a running total of everything earned. **Ping** shows the ENet round-trip time measured by the host, in milliseconds; the host and solo players have 0 ms, disconnected players or connections that cannot be measured yet show a dash. The host requests a measurement every second and distributes the values through the game state; at the end of the round, the ping stays live through separate updates. Technical background: [ENetPacketPeer statistics](https://docs.godotengine.org/en/stable/classes/class_enetpacketpeer.html#enum-enetpacketpeer-peerstatistic).
