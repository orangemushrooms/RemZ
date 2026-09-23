RemZ - Windows x64

START
Extract the whole ZIP into one folder, then start RemZ.exe.
RemZ.pck must stay next to the EXE. Godot does not need to be installed.
To pass the game on, zip the complete contents of this folder.

CONTROLS
WASD: move, Mouse: look around, Left click/Right click: shoot/aim.
Shift: sprint, Ctrl: crouch, R: reload, 1-9/0: quick bar, Mouse wheel: weapon.
G: grenade, H: melee strike, E: interact, F: flashlight/repair tower.
I: inventory, B: drop Rem Dollars, M: map, Q: quests, Hold Tab: leaderboard.
T: tower build menu, R/Mouse wheel: rotate build preview, E: confirm build.
E at a tower: mount/dismount. Left click: fire. Hold right click: precision zoom.
R at an unoccupied tower: align. Upgrades/dismantling at Mechanic.
Escape: pause, F11: fullscreen.
Adjust graphics, sound and mouse sensitivity in the start/pause menu.

MULTIPLAYER
Main menu > Multiplayer / Hamachi. Up to four players, UDP port 24567.
All players need this same build. Details: MULTIPLAYER.md.

CONTENT
What's new in this release:
- The game is now in English. German is available under Settings > Language
  (Deutsch).
- The game is now called RemZ. Settings, co-op name, high scores and
  achievements from “Birkenhof Nacht” are carried over automatically the
  first time you start it.
- Earthworms: from wave 12, a giant worm burrows across the southern fields
  every four waves, and from wave 24 the 19-meter Grave Wyrm joins in. An
  orange earth ring warns three seconds before one surfaces; worms only take
  damage while they stick out of the ground.
- Boss music: every boss fight plays one of four original boss songs.
- Towers are unlocked by surviving waves (Sentinel from the start, then
  Flamethrower, Mortar, Heavy MG and Tesla Coil), for the whole team.
- Scope with its own crosshair; mouse movement gets finer as you zoom in.
- The Cryo SMG C7 visibly freezes enemies; frozen enemies take more damage.
- Dedicated firing sounds for the eight new weapons; the Flare Pistol no
  longer stutters.
- Main menu and restart without freezing, with a loading screen and the RemZ
  crest.

Still included: the eight new weapons (Desert Eagle .50, Flare Pistol,
MAC-10 SD, Cryo SMG C7, Plasma Rifle, Lever Action .45-70, Minigun M134,
Graviton Cannon), weapon mods, Rem Dollars, the Vendor introduction, quest
notifications with sound, longer breaks between waves, forest and gravel
paths, dusk with cricket sounds and fireworks.

Fixed: on the very first start, the half-built world flashed up, blown out
white, instead of the loading screen; now the loading screen is there from
the first frame. The intro's briefing and direction arrow no longer cover the
pause menu. Field titans destroy the gates from every approach direction
(before, the palisade itself shielded the gate), the open inventory stays
clickable in co-op, and two causes of crashes, in the co-op data sync and in
the trader window, have been removed.

MORE INFORMATION
VERSION.txt and BUILD-INFO.json: build, checks and checksums.
README.txt (this file), MULTIPLAYER.md, DEFENSE.md and PROGRESSION.md: player
guides. The German versions are included too: LIESMICH.txt, MEHRSPIELER.md,
VERTEIDIGUNG.md and FORTSCHRITT.md.
GODOT-LICENSES.txt, VALVE-LICENSE.txt and the ASSETS files: license and
source notes.
Diagnostic logs are written to the logs folder while you play.
