# The Planes: Forest systems and field fixes, 28 September 2026

This correction batch follows the published Planes co-op release `1fc47f7`.
It does not change the map into a hut-defence mission: surviving remains the goal.

## Player-facing changes

- The shared Forest HUD now supplies the reticle, hit feedback, health, Rem Dollars,
  class level/XP, clock, combat readouts and standard inventory. Only owned starting
  equipment occupies the quickbar: pistol, grenades and knife.
- Traders use the Forest Trade/Sell/Training/Towers/Mods layouts, greeting voices,
  gold reward feedback and quest markers. Mechanic sells normal training, portable
  defence kits and fortification upgrades. The field journal includes the range quest.
- Fourteen deer/stags and twenty-four birds are huntable. Named flowers and mushrooms
  enter the real brewing/food inventory with pickup sounds. The junction fire has
  a kettle and grill; ingredients make drinks, venison can be cooked, eaten or sold.
- Forest night crickets accompany the existing music, day/night and weather systems.
- The Forest wave catalogue supplies all 25 waves, bosses, titans and worms, with
  its party and difficulty scaling. Enter starts the next wave early. Kill streaks
  award bonus money and feedback. Six Planes achievements cover targets, collecting
  and survival milestones.
- Hold E for three seconds to revive a teammate; the HUD shows their name and progress.
  Releasing E, leaving range, losing line of sight or opening a menu cancels it.
  Reviving restores at least 65% health and grants four seconds of damage protection.
- Palisades rotate with the mouse wheel, snap end-to-end and upgrade at Mechanic.
  At a ground tower, Y opens relocation, E confirms and Esc cancels; T's planner
  retains its existing move controls. Mortar range is 120 m and blast radius 12 m.
  Titanbreaker's base damage is 840. These shared combat values also apply in Forest.
- Trees are rooted at their mesh trunk base and have solid trunk colliders. The field
  fence uses slim timber posts and three wires. Camp navigation follows the actual
  shallow depression. Crop LOD work is spread over frames to reduce periodic stalls.
- The co-op roster shows each player's class icon, class, level and readiness.
  The protocol is version 7; all peers need the same new build.
- Worm corpses use a cached whole-body falling animation, including the root track
  removed by the original glTF optimisation. Their final pose stays grounded before
  ordinary corpse cleanup. The fall timer also works without blood decals on clients.

## Schützenhaus

User anchor: **47.401614391076905, 8.333379393336026**.
The existing OSM footprint `118083383` places the house at local **(-122.015, 309.58)**.
It replaces the generic solid house proxy. The southern field outline now includes
the building and entrance; residential scenery remains outside the playable area.

The dark timber siding, pale west-facing door, tiled pitched roof and noticeboard
follow the supplied Street View and the club's exterior photograph. The interior,
furniture and game pickups are a playable reconstruction, not an interior survey.
The club confirms a 300 m range with six electronic targets:
[SG Remetschwil: Schiessanlage/Anfahrt](https://sgremetschwil.ch/startseite/ueber-den-verein/schiessanlage-anfahrt/).
Reference-only images are kept in `artifacts/planes/references/`, outside game exports.

The key has a 50% spawn roll at run start; if absent, each new night offers another
roll. It appears on a clear, reachable woodland stump inside the playable boundary.
Finding it unlocks the shared door and six shooting shutters. The house holds one
Ranger .308, one Titanbreaker .50, one shotgun, full reserves and an ammunition cache.
Pickups are shared, single-use world items; quest progress belongs to each player.
Accept the log inside, hit all six targets with a sniper **from inside the house**,
then return to the log for 350 R and class XP. The surveyed target distance is about
311 m between these model positions. Host validation prevents duplicate loot/rewards.

## Verification

Tests use `.test-user` or nonpersistent profiles, never the player's real saves.
Rendered captures live in `artifacts/planes/parity/`; test logs start with
`logs/planes-parity-`. The run covers real door traversal, six physical target rays,
actual pickup/brewing/grilling transactions, flush building collisions, wheel input,
camp zombie movement, all 25 accelerated wave transitions, Forest downed behaviour,
worm death and separate host/client multiplayer sessions including rematch.

The multiplayer integration checks purchases, personal inventory and XP, duplicate
requests, holding E to revive, plants, construction, range door/loot and an actual
networked sniper shot. It also checks cancelled E holds and moved towers' positions
and rotations on both peers. Forest's four-player regression passed 181 checks with
no failures. The lobby was inspected at 1600×900 and 1280×720 using different classes.

Final functional regressions (462 assertions, zero failures):

| Suite | Checks |
|---|---:|
| Planes parity, house access and target challenge | 50 |
| Planes boundary and player collision | 18 |
| Planes economy, construction and harvesting | 47 |
| Planes 25-wave lifecycle, weather and retry | 39 |
| Forest downed state and revival | 24 |
| Worm combat, grounded death and decal-free client corpses | 54 |
| Planes host/client integration, including rematch | 49 |
| Forest host plus three clients | 181 |

Final Godot import and compile passed: 353 scripts, zero broken scripts.
The German catalogue check passed with 2,136 entries and zero problems.

The Forest transport test deliberately attempts to bind a second host to an occupied
port; its expected ENet error is followed by the passing rejection assertion.

Same-machine rendered performance comparison (RTX 3060 Ti, 1280×720, uncapped,
same scene route/settings; no second user game running):

| Scene | Previous FPS | Updated FPS | Previous p99 frame | Updated p99 frame |
|---|---:|---:|---:|---:|
| Quiet field | 112.70 | 116.40 | 11.28 ms | 9.14 ms |
| 40 towers, 40 walls, 24 enemies | 72.05 | 87.42 | 36.01 ms | 15.87 ms |
| Same fortifications in a storm | 70.92 | 83.79 | 30.41 ms | 17.09 ms |

These are measured samples, not a guarantee of identical results on other hardware
or of zero stalls in every possible match. Online EOS transport was verified for the
previous published release; this batch's multiplayer regression uses real local
ENet peers. The known Windows certificate-store warning is separate from game script
errors and remains present in this test environment.
