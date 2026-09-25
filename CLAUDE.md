# RemZ

First-person zombie survival, built in **Godot 4.7** (folder `godot/`). The user (Michel) does no manual work in
editors; Claude generates assets and code. Reply in German (Swiss spelling, "ss" not "ß").

The game is called **RemZ** (project name, window title, EXE). Until 23 Sep 2026 it was "Birkenhof Nacht", and
Godot keeps user:// in `app_userdata/<project name>`, so `legacy_user_data.gd` (`LegacyUserData.import_once()`, the
first thing in `main._ready`) brings the old saves over once: settings.cfg and network.cfg when missing,
achievements as a union, high scores merged to the top 10, marker `legacy_imported.txt`. Caches stay behind.
`--suite=legacy_user_data` (headless, 11 checks) works on temp folders only, never on the real saves.

## What the game is
- Autumn forest campsite at dusk, look modelled on a reference image: warm haze, leaf-covered ground, cabin,
  campfire with cauldron, log benches, pumpkins, mushrooms. Graphics quality beats framerate: the target is a
  strong gaming PC, everything runs at max settings.
- Level = the real **Waldhütte Remetschwil** (Sennhof, Heitersberg, 47.40994 N / 8.3399 E, OSM way 36785519).
  Built 1:1 from geodata, look from the user's site photos (`Fotos for map creation with annotation/`, 25 photos
  with a map inset; see the "Map" section below). The hand-drawn plans `Map_1.jpeg` / `Map_2.jpeg` are
  schematic and rotated: plan-north = real east, plan-east = real south, plan-south = real west, plan-west = real
  north. The user describes directions in the plan's frame ("Nordstrasse" = Sennhofstrasse, which really runs
  north-south on the east edge; "Wiese" is really south of the Weg zur Hütte; "Waldweg nach Hütte" comes from the
  north). Translate before touching positions.
- Systems: waves (10 + 5 n zombies times the difficulty factor, boss wave every 5th with brutes, 27 m field
  titans from wave 6 every third wave, `Waves.MAX_ACTIVE` 72; since 25 Sep 2026 the common horde gains +6 %
  health per wave (`EncounterBalance.horde_hp`, capped x2.5 - bosses keep `heavy_hp`), runners from wave 1,
  soldiers from wave 2, brutes from wave 3 with a growing share, speed +4.5 % per wave, 120 s intermission,
  Normal = hp 1.15 / dmg 1.25 / count 0.95 / speed 1.04 since the evening of 25 Sep 2026 - a notch gentler on request, Nightmare hp 2.0 / dmg 2.3), a closed palisade ring (`perimeter.gd`) whose
  only openings are the 4 barricade slots = gates (E / planner V; the player vaults a built gate with Space), the
  Waldhütte's own health (`hut_health.gd`, 5000 HP: 35 % of the zombies are "raiders" that head for its walls once
  inside the ring, every zombie within 9 m of a wall hits it, titan strikes hurt it, HUD line under the wave bar,
  minimap pulse and `HutHealth.WARNING` ("WARNING: THE FOREST HUT IS UNDER ATTACK!"); E at a wall repairs 500 HP for 30 P; at zero the
  round is lost, `main._hut_lost` / `CoopWorld.hut_lost`; `--suite=hut_health` has 19 checks), 17 buyable weapons with
  COD-style recoil + ADS (the eight from the September 2026 expansion carry a `special` block, see
  `weapon_specials.gd`), melee gun butt (H), grenades (G), quest tracker (Q), live round leaderboard (hold Tab), inventory (B), 6 zombie types with
  several Meshy skins each (`Zombie.TYPES[..].skins`, picked at random per zombie, missing GLBs skipped), supply drops
  from kills (ammo / grenade / medkit, walk through), kill streaks (+10 % per kill from the 3rd within 4 s, score
  popups), 4 difficulties (`GameSettings.DIFFICULTIES`, chosen in the start menu, saved), run statistics and a
  persistent top-10 table (`run_stats.gd`, `user://highscores.json`), 28 achievements, fleeing deer, procedural
  ambience (fire, birds, footsteps per surface, heartbeat when low; the wind is the user's own recording
  `sfx/Forest_Wind_Ambiance.mp3` since 25 Sep 2026, looped in `ambience.gd` at -6 dB under the trees, -10 on
  the meadow, -13 at the forest edge - it replaced both synthetic beds, `rustle` is an alias of `wind`) plus recorded music/SFX, HUD with
  low-health vignette, hit-direction arcs and a wave progress bar. The start / pause / game-over menu is one
  tabbed card in `hud.gd` (Briefing, Multiplayer, Difficulty, Controls, Settings, High scores, Achievements, Summary).

## Code map (`godot/scripts/`)
`main.gd` builds the whole world in `_ready` (terrain from the heightmap, road ribbons, forest via `trees.gd`,
deep-forest blocker, the two huts built from boxes with photo textures, campsite props, pasture fence, clutter,
foliage) and wires the systems. `map.gd` loads `assets/map/` (see Map) and exposes `ground_height`, cover
weights, roads, buildings, spawns, barricades. `trees.gd` procedural beech / oak / spruce (trunk meshes with
photo bark, leaf-card crowns with fake sphere normals, MultiMesh per species and 48 m cell, cylinder colliders).
`foliage.gd` PBR materials, 3-way terrain blend shader (forest floor / meadow / gravel from vertex colour),
ground leaves / grass multimeshes, falling leaves, campfire. `player.gd`, `weapons.gd`,
`grenade.gd`, `zombie.gd`, `waves.gd`, `barricade.gd`, `skills.gd`, `deer.gd`, `ambience.gd`, `sfx.gd`, `music.gd`, `hud.gd`,
`pickup.gd` (drops), `run_stats.gd` (statistics + high scores), `game_settings.gd` (profiles, difficulty, config),
`weapon_specials.gd` (the expansion's mechanics: plasma heat with venting, minigun spin-up, the
cryo freeze that builds up hit by hit, the flare projectile with its light, the graviton blast;
runtime values live in `state[id]`, never in `state[id].def`, which every mod change replaces),
`perimeter.gd` (palisade ring: `CORNERS` between the gate endpoints, log/rail MultiMeshes, collision boxes in the
`navsource` group so the navmesh only connects outside and inside through the gates; the wall body also joins
`perimeter_wall`, which `Titan.clear_strike_line(.., .., true)` lets a slam pass so the wall cannot shield the gate
it carries - without it a titan standing anywhere but exactly square to a gate hammered it forever for no damage
(`--suite=titan_siege_gate` checks all four gates from five angles); `contains()`, `points`,
`gate_edge`; `tools/plot_perimeter.py` overlays the ring on roads and terrain before touching a corner),
`barricade.gd` (the gates themselves, 25 Sep 2026: three upgrade tiers in `Barricade.TIERS`, each with its own
Meshy wall - `barricade` timber palisade 300 HP / 50 R, `barricade_iron` iron-banded log wall 800 HP / 120 R /
30 % armor, `barricade_steel` (the `_plain` retexture without emblems) steel bulwark 1600 HP / 220 R / 50 % armor;
armor is the share of every hit shrugged off, `_make_segment(level)` turns the GLB's longest side along the line
and scales it into the 3.2 x 1.55 m segment, a missing GLB falls back to the timber model with steel bars; the
planner in `barricade_menu.gd` reads the same table; `--suite=barricades --render-barricades` (windowed) renders
every tier into `artifacts/barricades/`),
`weapon_attachments.gd` (hangs the mod models on a weapon; see Weapon mods).
Batch of 25 Sep 2026 (`--suite=forest_finds --smoke-test --no-intro --no-music --no-foliage`, 35 checks;
`--render-finds` windowed saves `artifacts/finds/{trip,mushroom,attack-arrows,headshot}.png`):
- Palisade hits: a zombie swing that the ring blocks (`Zombie._can_hit` sets `_blocked_by_wall` when the ray
  stops on the `perimeter_wall` body) damages the nearest built gate by `WALL_HIT_SHARE` 0.6 of the swing
  (`_hit_palisade`) and raises its attack alert; before that those swings did nothing. `hud.gd` draws pulsing
  red arrows with the gate name around the crosshair for every gate (and the hut) `under_attack()`
  (`_update_attack_dirs` / `attack_dir`, same angle convention as the hit arcs).
- Lethal headshots burst the head: `Zombie._pop_head` scales the Head bone's pose to 0.001 (the Meshy clips
  carry no scale tracks, so the death clip leaves it; a SkeletonModifier3D was tried and Godot restores poses
  after modifiers), sprays three pooled `weapons._blood` bursts and plays one of five baked `head_burst_1..5.wav`
  (`tools/build_head_burst_audio.py`: pumpkin splat + flesh noise + thud + bone cracks + drips, seeded) at a
  random pitch 0.88-1.14 and -9..-4 dB, so no two heads pop alike (the single fixed pop was the complaint). Replicas get the
  flag as zombie snapshot field 13.
- Mara's search quests (`Progression.FINDS`, quests `pond_cache` / `trip_mushroom` / `maze_crate` in the
  forest chain): one node each, placed by `place_finds()` from `place_cache()` - the box at the pond shore,
  the violet glowing mushroom at a random forest spot 55-150 m from the fire, the crate on the dead-end
  passage farthest into the maize maze; E via `nearest()` / `transact(.., id, "find", "")`, goal
  `team["find_<id>"]`, minimap marker once accepted, co-op snapshot `finds`. Eating the mushroom calls
  `hud.hallucinate(28)`: a full-screen `TRIP_SHADER` ColorRect (wobble, mip blur, chroma shift) fading in
  and out (`_update_trip`, `tripping()`), sent to a client as feedback "hallucinate".
- The flashlight switches itself on at 19:00 game time once per night (`main._auto_flashlight`, message
  "Night has fallen. Flashlight on - toggle it with F."); the player may switch it off again.
- Training at the Mechanic costs `Skills.training_cost` = twice the listed base (tier 1 of Firepower 240 R).
- Secret Night, the long version (`secret_night.gd`, 25 Sep 2026, `--suite=secret_night` 66 checks, `--visual`
  windowed saves `artifacts/secret-night-{floor,side,farewell,echo}.png`): 12 stages - follow the sound,
  tune the totems, `HARVEST` (pick the three glowing mushrooms at `GLOW_SPOTS`, `harvest_mask` bits), `TRIP`
  (eat the DJ's mushroom at the bar: `_trip_everyone` = `hud.hallucinate(18)` for every actor), `COLOUR_RUN`
  (`RUN_SEQUENCE` pink / violet / turquoise / violet, reach the flashing totem within `RUN_SECONDS` 10 each,
  too slow restarts the run), `CLEAR` (Clear Head drink, `hud.sober()` / feedback "sober"), `DANCE_STEP`,
  `GUESTS` (`_spawn_ravers`: eight zombies rise around the floor, cleared = `main.alive_zombies() == 0`),
  then CLOSING / ECHO / RETURN / WAKING as before; reward 250. `DANCE` moved to (-108, -192) and dancers never
  spawn at z < -197: the circle used to reach into the stage proxy (front at z -199.5) and the dancers stood
  inside the DJ desk. Snapshot carries harvest / run_round / run_target / run_time / ravers.
- Tower planner (`tower_planner.gd`, 25 Sep 2026): T opens a bird's-eye orthographic view (`overview`, size 68 m
  above the hut / fire midpoint) with the tower types on a card (keys 1-5), the six roof slots as gold rings
  and buttons, the ghost following the mouse (`point_at` rays through the overview camera), click = build
  anywhere within `PLANNER_REACH` 45 m of the player without the line-of-sight rule (`placement_error(..,
  planner = true)`), drag a standing ground tower to relocate it for free (`DefenceSystem.relocate`, co-op
  command "tower_move"), R / wheel turn the hovered tower (`rotate_tower(.., planner)`) or the ghost. Solo it
  pauses like the barricade planner. The old list menu (`begin_building`, `site_picker`) stays for the tests.
  Second pass: the view is 34 m wide on the hut (`VIEW_SIZE`, +/- zoom 18-80; farther than
  `HUT_VIEW_RANGE` 22 m from the hut the map opens over the player instead, so the meadow can be planned), a click within `ROOF_SNAP`
  2.2 m of a roof ring goes onto that slot (`roof_slot_near`), and from the planner the roof takes turrets
  from anywhere within `PLANNER_REACH` while the hut stands (`placement_error` planner_roof).
  `--suite=tower_planner` (23 checks), `--render-planner` windowed saves `artifacts/tower_planner/planner.png`.
- Quests count from acceptance (`Progression.progress_value`, baseline per peer and quest in `data.baseline`,
  cumulative kinds in `CUMULATIVE_GOALS`); the horde scales with the party (`EncounterBalance.party_hp` /
  `party_damage`); titan steps: cue shake 0.75 / 120 m plus the heavy sway in `Player._update_tremor`.
- Zombie deaths (25 Sep 2026, second pass): every common skin carries five Meshy library deaths - 184 forward,
  189 crumple backward, 185 slow fall backward (`death4`), 188 belly fold (`death5`, direction-neutral) and
  183, the stiff plank drop with the arms out, which `_death_clip` never picks (`is_plank`: hands wider than
  `PLANK_SPREAD` 14.5 shoulder widths 40 % into the fall; `is_crumple`: under 8 the whole way). The metrics
  (`travel_z`, `spread_mid`, `spread_end`) come from `zombie_animation.measure` at load - seeking the live
  rig for them left the first body of every model lying flat before its fall (the "they just end up on the
  ground" bug). Only a shot clearly from behind (`local.z > 0.35`) drops the body onto its face.
  `tools/zombies_v3.py` SHAMBLE / RUNNER carry death4 / death5 (3 credits per clip and skin);
  `tests/death_clip_audit.gd` prints the numbers, `--suite=gore_visual` (windowed, `--no-foliage`) renders
  five deaths and cuts into `artifacts/gore/`.
- Dismemberment (`zombie_gore.gd`): at load every skinned mesh is cut into a body mesh plus head / arms / legs
  by the dominant bone weight of each triangle (`ZombieGore.prepare`, cached per model, called from
  `preload_models` and `setup`); each zombie gets one skinned MeshInstance3D per part on the same skeleton
  (`attach`, after `_build_hitboxes` because the hit shapes are keyed on the original mesh node). `sever`
  hides the part, hangs a dark stump on the joint (BoneAttachment3D), spurts pooled blood four times and
  throws the part's rest-pose geometry off as a RigidBody3D chunk (frozen after 6 s, gone after 14).
  Zombie side: `LIMBS`, `last_hit_bone` from the HitVolume, 40 % health per limb or a 30 % single hit,
  arms halve / end the swings, a leg drops the body, the head cut is the headshot burst, snapshot field 14.
  Horde bench unchanged (60 zombies 108-119 FPS). A PhysicalBone3D ragdoll was tried and dropped: Godot's
  simulator drifts the bodies every frame under the 0.01-scaled Meshy skeletons.
- Secret Night ends at the next morning (`MORNING_SECONDS` 06:42, `_update_morning`: 90 s of thick fog for the
  sun shafts and a 5 s wake-up flash), no map marker before the echo, bar sign at y 4.9, trip 36 s, 30 s to
  prepare.
- Hallucinogenic mushrooms in the forest: `Mushrooms.DEFS.kahlkopf` (Liberty Cap, weight 8, procedural
  model with a faint violet emissive cap, `"trip": 25.0`). Any kind with a `trip` key calls
  `hud.hallucinate(trip)` when eaten (`inventory._eat`, `coop_world.eat` sends feedback "hallucinate" to a
  client) on top of its buff (+50 % damage for 30 s) and counts for the "rausch" achievement. Icons for
  new mushroom kinds: `--script res://tests/run.gd -- --suite=render_item_icons --only=kahlkopf` (windowed;
  through run.gd so Lang / NetSession exist - called directly the mushroom script does not compile) then
  `--headless --import`; kinds without a GLB render their procedural model.
Batch of 26 Sep 2026 (weather, moon, special infected, titan phases, sandbags, down / callouts / purse):
- Weather (`weather.gd`, `main.weather`): states clear / fog / rain / storm, one schedule per game day
  (day 0 is scripted: fog 06:20-08:00, rain 16:30, storm 18:00-19:24, rain until 20:36; later days roll
  fog 55 %, rain 50 %, a storm inside a third of the rains). Host and solo decide, clients mirror the
  snapshot field "weather" `[state, intensity, wind.x, wind.y, lightning_serial, wetness, day]` and replay
  every bolt from its serial (seeded distance and direction, so flash timing and thunder delay agree).
  Effects: `DayNightCycle.weather_dim` / `overcast` on sun, fill and fog, the sky shader uniforms
  `overcast` / `flash` / `moon_phase` / `moon_tint` / `moon_size`, `env.fog_density` and
  `volumetric_fog_density`, one GPUParticles3D of rain streaks around the camera, four `FogVolume` banks
  drifting with the wind, a rain loop (`secret_rain.wav`, muffled under the hut roof) and the shader global
  `remz_wetness` (project.godot `[shader_globals]`; terrain, ground sprites, leaf cards and bark darken and
  get glossy, soaking in 28 s, drying in 110 s). Lightning: `Zombie.lightning_reveal()` makes every zombie
  glow cold white for 0.45 s, the sun jumps to 9, thunder (`thunder_1..3.mp3`, the user's recordings; `tools/build_weather_audio.py`
  bakes only the synthetic fallbacks that are left) arrives after distance / 343 s with a tremor. The intro and the secret
  night keep their own fog (weather goes clear while they run). `--weather=<state>` pins a state; the cheat
  menu has the same plus "Release".
- Moon (`day_night_cycle.gd`): `night_index` counts every crossing of 20:00 (`night_began`), the phase runs
  over `MOON_CYCLE` 8 nights (`moon_phase()`, `moon_phase_name()`), every `BLOOD_MOON_EVERY` 5th night is a
  blood moon from 20:00 to 05:00 (`blood_moon()`, `blood_moon_changed`): red full moon, red moonlight and
  fog, `Zombie.horde_pace` 1.25 on every zombie's ground speed (titans too) and double points in
  `main._zombie_killed`. `set_time_hours` and `apply_moon` (co-op, snapshot "moon") re-evaluate it.
- Special infected (`Zombie.TYPES`, models by `tools/zombies_v3.py` specs + `tools/creature_models.py`):
  `spitter` (`"ranged"`: lobs an `AcidGlob` at a gate, the hut wall or the player from 5-17 m every 4.2 s;
  the landing spawns an `AcidPool` that eats gates, sandbags, towers and the hut wall for 6.5 s and burns
  players standing in it; host only, clients get `NetSession._acid_glob` / `_acid_pool`); `screamer`
  (`"screamer"`: on sight within 24 m it screams once per 22 s, `main.horde_call`: the player is
  `marked_t` 12 s for every zombie (`main.marked_player`, pink ring on every minimap, "SPOTTED" on the HUD),
  every zombie within 70 m hunts them, three runners join the wave from the nearest lane
  (`Waves.reinforce`); `stalker` (`"stalker"`: only planned while `Weather.hides_stalkers()` - fog, rain,
  storm or night - and spawned inside the standing maize by `Waves._try_corn_spawn`; `cloak` 0.07 unless a
  flashlight beam (anyone's, `_lit_by_flashlight`), a swing, a hit, lightning or death lights it, materials
  through `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`, off the minimap while hidden); `zombie_dog` and
  `zombie_stag` (`"beast"`, `zombie_beast.gd`: rig-less Meshy animals fitted by height, gallop bob and
  lunge from the real ground speed, the stag charges from 4-28 m with a clear line, rams players (shove)
  and gates, wheels away between charges, both fall onto their side when killed; bullets hit the capsule).
  Plan: dogs from wave 3 on odd waves, the stag from wave 6 (never a boss wave), screamers from wave 6,
  stalkers from wave 4, spitters replace 8 % of the horde from wave 4 (`Waves.dog_count` etc., all in
  `preview_count`).
- The mutation: from wave 10 `Waves.armor_chance` (20 % to 45 %) of shamblers, soldiers, brutes, spitters
  and nurses spawn `armored` (main.spawn_zombie; `armor_override` for the cheat menu): a helmet
  (`zombie_helmet.glb`, fallback a steel dome) on the Head bone through a BoneAttachment3D, sized in bone
  space (`1 / world_scale`). `Zombie.hit_helmet` in the weapons pipeline: a headshot on `helmet_hp > 0`
  rings off (`helmet_ping.mp3`), 20 % reaches the body, no headshot bonus; at zero the helmet tumbles off
  as a chunk and heads pop as usual. Snapshot fields 15 / 16 (`helmet_hp`, `armored`), `apply_helmet`.
- Titan phases (`titan.gd`): below `ARM_LOSS` 65 % the right arm collapses (`_apply_lost`: bone scale,
  stump, blood, rage roar) and the giant throws trees (`thrown_tree.gd`: trunk, root ball and crown on an
  arc every 9-15 s at a player 14-80 m away; `ThrownTree.RADIUS` 5.5 m crushes players (shove), gates,
  sandbags, towers, the hut and zombies; `NetSession._titan_throw` replays the arc on clients); below
  `LEG_LOSS` 35 % the left leg goes and it crawls (`CRAWL_TILT`, half speed, slam radius 0.75 and windup
  0.6). `boss_state()` carries `lost` and `throw_serial`; replicas mirror the collapse.
- Sandbag lines (`sandbag_line.gd`, `main.sandbags`, one per gate, `SandbagLine.FALLBACK_DEPTH` 9 m inside
  the ring, same direction): a site until the gate falls (`Barricade.breached` -> `main._gate_breached`
  -> `deploy()` for free), then a 450 HP wall (visual 0.95 m, collision 1.25 m so the zombies' 1 m sight
  line cannot skip it), armour 0.2, repair 40 R, rebuild 60 R with E, vaulted with Space (the vault ray
  now runs at 0.65 m). `main.defence_lines()` = gates + sandbags is what zombies, acid and trees hit;
  `Barricade.is_gate()` keeps palisade hits, the planner and the ring on the gates. Snapshot "sandbags".
  Barricade gained `wall_height` / `collision_height` / `segment_scene` / `armor` / `hit_sound` /
  `breach_message` for the subclass.
- Down instead of dead (`player.gd`): at zero health `go_down()` - `DOWN_SECONDS` 25 s bleed-out, crawl
  at 40 % pace, still shooting, every hit costs `HIT_BLEED` 0.12 s per point; holding E for
  `SELF_REVIVE_HOLD` 4 s gets up with 40 HP once per wave (`self_revives`, restored by every cleared wave,
  which also lifts a downed player with half health); at zero `_bleed_out()` -> `died` (solo "YOU DIED").
  Co-op: the host runs the hold (command "self_revive" true/false -> `revive` dict, target == self), a
  teammate's E (3 s, "revive") works on downed and dead players, `wave_cleared` restores everyone;
  snapshot `players[id].down = [downed, down_time, self_revives, marked_t, revive_hold]`; `player.shove`.
  HUD: `set_downed` (bleed and hold bars above the prompt), `--no-downed` restores instant death.
- Callouts (`pings.gd`, `main.pings`, action `ping` = X or middle mouse): `contextual()` pings what the
  crosshair rests on (gate under attack / breaking / hold, sandbags, hut, enemy, ground = move, nothing =
  regroup; an open site along the sight line counts), the game calls out breaches, downs, screamer marks,
  titans and the blood moon (`callout` with a 12 s cooldown per key). Every ping: radio log top left,
  a diamond marker in the world (`hud._draw_pings`) and on the minimap for 9 s, `radio_ping.wav`.
  Co-op: command "ping" -> host validates -> feedback "ping" `[author, kind, position, subject]`; the text
  is built on each machine (`Pings.TEXTS`, gate names translate, player names stay).
- Team purse (co-op): `coop_world.purse`, deposits of 50 / 100 / 250 R from the planner (command
  "purse_deposit"), `Barricade.purse()` / `spend()` pay gates and sandbag lines from the fund before the
  buyer's pocket, every cleared wave adds 10 + 3 x wave. Snapshot "purse". Solo has no fund.
- Suites (all headless, `--smoke-test --no-intro --no-music --no-foliage`): `weather` (55), `new_zombies`
  (61), `titan_phases` (22), `sandbags` (43), `downed` (22), `pings` (19), `team_purse` (29, hosts an
  offline session like coop_snapshot_cost), `forest_spirit` (23, the second session's boss: rig, clips,
  bone volumes, the pulse, boss state, wave plan, forest spawn). Windowed: `batch26_visual` renders the
  batch into `artifacts/batch26/*.png` (line-up in the rain, storm flash, blood moon, fog banks, crawling
  titan and its tree, sandbags with acid), `sandbags_visual` only the line. `tools/run_regressions.py`
  runs the regression list three at a time into `logs/t_*.log` and `logs/regressions_summary.txt`.
  Older suites that assumed instant death or damage without the difficulty multiplier were adjusted
  (menu_flow, smoke, multiplayer bleed the downed player out; earthworms / titan_variants multiply by
  `difficulty.hp` / `damage_mul`; zombie_hitboxes / horde_hit_precision skip beasts and bone-volume bosses;
  missing_models accepts the procedural liberty cap).
- Forest Spirit (second session, 26 Sep 2026): `forest_spirit.gd` (`"boss": true` in TYPES, locally rigged
  `zombie_forest_spirit.glb` from `tools/rig_forest_spirit.mjs`, five bone-following Area3D volumes, a
  pulse every 11 s that throws players back, replaces one lesser titan in 22 % of those waves and enters
  through the woods). `Zombie.is_boss_kind` counts "boss" kinds; they skip baked hulls and gore.
Scenes are built in code; `scenes/main.tscn` only holds the root. Kills are scored in `main._zombie_killed`
(difficulty multiplier, streak bonus, headshot x1.5); zombies only report through the `_on_kill` callback.

## Map (`godot/assets/map/`, generated, committed)
- `tools/geo_fetch.py` downloads swissALTI3D 0.5 m tiles (STAC), OSM (Overpass) and a swissimage WMTS mosaic
  into `input/geo/` (gitignored, ~40 MB); `tools/geo_fetch_wide.py` adds `aerial_wide.jpg` (x -480..300,
  z -300..430, 10 cm) covering Sennhof, the north edge of Remetschwil and the hamlet in the west. swissimage is
  the same imagery Google Maps shows for Switzerland, so it is the 1:1 reference for the village. `tools/build_map.py` turns them into `heightmap.f32` (float32 LE,
  1 m grid, rows = z south, cols = x east, metres relative to the fire, 659 m a.s.l.), `ground.png`
  (R forest floor, G meadow, B gravel), `map.json` (extent, roads as polylines with surface/width, hut boxes,
  campsite objects, fence lines, spawns per lane, barricade slots, 3300 tree positions with species from the
  aerial colour, shrubs) plus `tools/out/map_preview.png` and `tools/out/terrain_viewer.html` (three.js) for
  checking. All hand-tuned layout numbers live at the top of `build_map.py`; rerun it after changes. Both
  aerials are resampled to exactly 10 px per metre before the 1 m block statistics (until 19 Sep the main aerial
  was squeezed to 9 px blocks, which shifted every aerial-derived feature by up to 40 m to the south-east).
  With the wide aerial the border trees follow the real crowns (closed forest, single trees around the farms,
  nothing on the fields) and every village footprint carries `roof` (median sRGB from the aerial), `ridge`
  ("long" / "short" / "flat" from the brightness step between the two slopes) and `dark_frac` (solar panels);
  `village_buildings.gd` picks tile vs. slate, ridge axis and flat roofs from that. Farm-yard props (silage
  bales, tractor, two cars) are placed by `main._village_props` at aerial positions.
- Coordinates: x east, z south, origin = OSM picnic node 427671292 (fire is at (7, -7) after the photo analysis).
  Godot yaw = -deg_to_rad(yaw_deg) of the JSON (python rotation convention is mirrored).
- Layout facts from the photos (re-checked 19 Sep 2026 against all 25 photos and the aerial): Waldhütte =
  concrete garage storey with the garage door in the west face (north end), red board upper storey, **gable roof
  with the ridge east-west** (the gable faces the track in the west with a 1.4 m overhang on purlins and knee
  braces, eaves along the north and south faces, mossy grey tiles, small ridge vent), 12 concrete block steps
  without railing along the north face from 2.5 m east of the north-west corner up to the upper door at the east
  end, two small cellar windows in the base near the south end of the west face, east side buried in the slope.
  The fire plaza is one level place (terrain flattened by the `PLAZA` polygon in `build_map.py`). The real one
  is gravelled, but the game keeps forest floor there on purpose - only the mapped tracks carry gravel, and
  `range_steps` asserts "leaves" at the fire. Do not "fix" this back to gravel. It holds four log
  benches around the square stone fire pit with swivel grill at (7, -7), picnic table on leaf litter 3 m west of
  the west bench, hollowed grey log fountain on log blocks with a thick trunk post and iron spout at the plaza's
  west edge (-2, -13), white steel drum bin on a post (-0.5, -16), info board + sign east of the Waldweg entrance
  (-5.5, -21); the Waldweg nach Hütte leaves the plaza's north-west corner at (-4, -11). Holzlager = brown
  corrugated/board walls, light fibre-cement gable roof (white in the aerial) with a 1.4 m overhang on struts on
  the road side, its ridge runs at 14 deg (not the 23 deg of the OSM outline), the big double door is 1 m from
  the south-east corner. The gravel track between the huts leads south to the fork with the Weg zur Hütte (east,
  along the forest edge with an open grass verge to the field, **no fence**, landmark oak at (66, 34)), the
  Wiesenweg (south onto the meadow, houses of Remetschwil on the horizon) and the Weg Richtung Dorf (west). The
  only fence is the wire fence on the east side of the Sennhofstrasse south of the junction. The Sennhofstrasse
  leaves the forest at the guidepost (124, 21) where the Weg zur Hütte branches off; north of it the road runs
  through dense forest on both sides. The Alps are a low band on the far horizon (sky `elevation_scale` 4.6).
  West of the Feldweg West and south of the Weg Richtung Dorf everything is farmland (the aerial classifier read
  the dark maize field as forest; `MEADOW_FORCE` now covers it), so the Weg Richtung Dorf has open fields on its
  south side all the way to the map edge. The village backdrop (`village_buildings.gd`, OSM footprints outside
  the extent) is Sennhof / Remetschwil farm style: white one- or two-storey houses under steep tile roofs, dark
  timber barns, long farmhouses with the barn under the same roof, never more than two window rows. The guidepost
  at the Waldweg entrance is procedural (`_sign_arrow`, Label3D): "Oberrohrdorf" on top points north,
  "Remetschwil" below points south.
- `tools/photo_textures.py` cuts tileable textures out of the photos into `godot/assets/textures/ph_*` (gravel,
  asphalt, forest floor, meadow, 4 barks, cladding, concrete, corrugated metal) and draws the leaf card sprites
  `assets/sprites/leaf_{beech,oak,spruce}.png` with colours sampled from the photos. Photo regions are in the
  1000 px thumbnail frame; the map inset (bottom right) must never be used.
- Godot's own PNG loader strips 16-bit, hence the raw float heightmap. `HeightMapShape3D` is the terrain
  collider; the render mesh is the full 1 m grid.

## Assets
- The eight expansion weapons (Sep 2026) come from `tools/weapons_expansion.json` +
  `tools/weapons_expansion.py` (resumable, four at a time; **Meshy rejects a prompt over 800
  characters with a bare 400**): deagle, flare_pistol, mac10, cryo_smg, plasma_sniper, lever_rifle,
  minigun, graviton_cannon. Their sounds are baked by `tools/build_weapon_audio.py` out of the
  user's own library (the unused clips in `music/Weapons/`, `Silenced_Tower`, `anti_tank_tower`,
  `Water_Tower`, `time_stop`) into `godot/assets/audio/sfx/weapons/*.wav`, in the same style as
  `prepare_tower_audio.py`. Exception: the flare shot is the user's own recording `input/audio/Flaregun.mp3`
  (only the 57 ms of dead air in front are trimmed, played at -9 dB = pistol level); the tool falls back to
  the synthesised thump when that file is missing. The weapon id equals the model name for all eight, which is what keeps
  the two namespaces (GRIPS/PROFILES by id, MountData/MAGAZINE by model) from drifting apart.
- Meshy API (key in the file `Meshy Key` in the repo root, export it as `MESHY_API_KEY`, never print it).
  Prompts in `tools/assets.json`. `python tools/gen_asset.py <name> --pbr --polycount N` (preview + refine,
  ~6 min, runs fine with 6 in parallel) then `node tools/pack.mjs <name> --size 2048` and copy
  `public/models/<name>.glb` to `godot/assets/models/`, then `Godot.exe --headless --path godot --import`.
  `python tools/retexture.py <name> "<prompt>" <suffix>` re-textures an existing model (used to strip the
  gibberish lettering Meshy paints on crates and bins: ask for "no text, no letters"). Windows: set
  `PYTHONIOENCODING=utf-8 PYTHONUTF8=1` or the progress bar crashes.
- The Waldhütte's cladding and leaf sprites come from `tools/gen_hut_textures.py`: `ph_boards_*` (horizontal
  red-brown tongue-and-groove boards, 9 per metre, sRGB matched to photo 14) and `leaf_beech/oak.png` (1024 px
  twig clusters with veined leaves, a few yellowing). The hut roof is dark corrugated fibre cement
  (`ph_corrugated`, grey tint), not clay tiles. The leaf shader adds per-tree hue/value variation (hash of the
  crown centre), a September `autumn` yellowing on some trees and `BACKLIGHT` translucency.
- Props are Meshy models placed through `main._prop(parent, name, size, axis)`: it turns the model's longest
  horizontal extent onto local +x, scales by length (`axis` "x") or height ("y"), puts the bottom on the ground,
  applies `PROP_YAW` / `PROP_TINT` and returns null when the GLB is missing so every call site keeps its old
  box version as fallback. Models (Sep 2026): log_fountain, waste_bin, guidepost, info_board, fire_pit,
  log_bench_beam, log_picnic_table, fallen_log, workbench, ammo_crate (loot), ammo_pack / medkit (drops,
  `pickup.gd`). `tests/prop_info.gd` prints AABB and triangle counts of the GLBs; `--spawn-drops` with
  `--views=` puts the three drops on the plaza for a look.
- Weapon mods (Sep 2026): every mod in `weapon_mods.gd` carries a Meshy part - `mod_suppressor`,
  `mod_compensator`, `mod_ghost` (Mündung), `mod_extended_mag`, `mod_endless` (Magazin), `mod_quick_action`
  (Verschluss), `mod_match_barrel`, `mod_titan_core` (Lauf) plus `mod_mag_tube` for the tube fed guns.
  `weapon_attachments.gd` mounts them: `MOUNTS` holds only intent per mod (which anchor, calibre as a multiple
  of the bore, longest allowed share of the weapon, how deep it sinks in), every offset comes from
  `weapon_mount_data.gd`, which `node tools/weapon_geometry.mjs --all-weapons --bake godot/scripts/weapon_mount_data.gd`
  (and a second run with `--parts <mod...>`) measures out of the GLBs: bore centre and radius from the frontmost
  vertex slab, magwell from the lowest vertices ahead of the stock, part axes by PCA (mod_ghost sits 15 deg
  askew in its own file, mod_endless is a disc). Rules that matter: the mount node is added to the holder only
  after `Hands.weapon_bounds` / `aim_position` are taken, so a suppressor never moves a grip or the sights; a
  barrel mod extends the bore first and the muzzle device then threads onto its tip; `muzzle_transform()` asks
  the mount for the muzzle, so flash, smoke and tracers leave the can, and with nothing mounted they leave the
  measured bore instead of the old bounding-box guess (that one put the titanbreaker's flash in its scope).
  `MAGAZINE` says what a weapon feeds from - box, tube, or nothing for the revolver. `equip_mod` and
  `apply_mod_snapshot` both funnel through `refresh_attachments`, and co-op avatars mount the same parts from
  the host snapshot (`coop_avatar.set_mods`, layer 1 and shadows on).
- Creatures of 26 Sep 2026: `zombie_spitter`, `zombie_screamer`, `zombie_stalker` are v3 skins (specs in
  `tools/zombies_v3.py`, folders `assets/raw/<name>_v3`, packed with `--simplify 0.62 --as <name>`; the
  stalker walks with library clip 559 "Sneaky Walk"). `zombie_dog` and `zombie_stag` come from
  `tools/creature_models.py` (nano-banana-pro side-view sheet -> image-to-3d Meshy 7.1, folders
  `zombie_dog_v2` / `zombie_stag_v2`, static meshes: Meshy rigs only humanoids) and `zombie_helmet` from its
  text-to-3d job. `tools/creature_variants.py` holds the cheaper retexture route (the first attempt, kept
  as reference: a retexture through `model_url` as a data URI works when the old task id is gone). The
  shot volumes were rebaked afterwards (17 meshes).
- Zombie skins, third generation (24 Sep 2026, `tools/zombies_v3.py`): every humanoid skin (the ten common ones
  plus zombie_titan / zombie_colossus) is a reference-first Meshy asset - `design` draws a T-pose sheet with
  nano-banana-pro (9 credits, look at `assets/raw/<name>_v3/design.png` before paying for the mesh), `model`
  turns it into a Meshy 7.1 mesh (4k geometry, 50-60k triangles, 4k PBR, 35 credits), `rig` at 1.7 m, `anims`
  buys the library clips per role (SHAMBLE / RUNNER / TITAN sets in the script, 3 credits each): walk + walk2
  (Frankenstein / Stumble / Elderly Shaky / Slow Orc walk), run (runner, jogger, nurse), attack + attack2,
  death .. death3, hit + hit2, idle, scream. `python tools/zombies_v3.py status` shows the stages, `redesign
  <name>` throws a bad sheet away. Then `node tools/pack.mjs <name>_v3 --size 2048 --albedo-size 4096
  --quality 88 --simplify 0.62 --as <name>` (merges every `anim_*.glb`, restores the normal and metal/roughness
  maps that Meshy's rig export drops, base colour 4k, other maps 2k, meshoptimizer takes the ten common
  skins from 50k to 32k triangles - Godot's imported LODs never kick in on Meshy meshes, and at 50k a 60-zombie
  horde cost 7 % more; titan and colossus stay at 60k without `--simplify`) and copy
  `public/models/<name>.glb` to `godot/assets/models/`, headless import, then rebake the shot volumes. The
  whole set cost about 970 credits. Text-to-3D alone lost the clothing of the prompt (a bare "rotting
  zombie"), the image step is what keeps farmer, hiker, nurse apart. Texture imports: albedo BC7
  (`compress/high_quality`), normal maps RGTC (`compress/normal_map=1`), everything VRAM compressed.
- Zombie animation layer (`zombie.gd`, checked by `--suite=zombie_motion`, 68 headless checks): `state` stays
  the logical state (walk / attack / death / hit / idle / scream) that the AI, tests and the co-op snapshot
  use, `clip` is the rig's concrete clip. `zombie_animation.measure()` samples every clip once at load
  (`Zombie.clip_info(path)`): the ground speed a gait implies from the foot travel and the strike moment of a
  swing from the hand speed. Gaits play at `speed_scale = displacement / natural speed` (no foot sliding, a
  27 m titan strides), a runner drops to walk below 1.9 m/s, standing bodies go idle after 0.35 s, swings
  are timed so the strike lands on the damage tick (`attack_lead()`, a titan's on the end of its wind-up),
  35 % of the zombies stop once to scream within 14 m, heavy hits play the flinch clip, deaths pick a random
  fall. Beyond 45 / 90 m the AnimationPlayer runs in manual mode and advances every 2nd / 3rd tick. Heads
  turn towards the player within 12 m (LookAtModifier3D on the Head bone, `--no-headlook`). Older rigs with
  only walk / attack / death still work: missing clips fall back to the gait. A swing keeps its clip for
  `attack_hold()` (strike + 0.45 s, at most the cadence) and a flinch for `HIT_HOLD` before the gait resumes,
  with a 0.3 s blend back; cutting them at the damage tick made the horde twitch (24 Sep 2026).
  `zombie_animation.prepare()` cleans every rig once at load: constant bone-length tracks go onto the
  skeleton, the horizontal Hips motion of every clip but the deaths is frozen (Meshy's library walk2 travelled
  3.4 m per loop and the runner sprint 3 m per 0.5 s, so the mesh ran ahead of its collider and snapped back),
  gaits whose ends do not match are cut to their best-matching window and the last 0.12 s of every gait glide
  into its first pose. `--suite=zombie_clip_audit` (headless, 232 checks) prints `CLIP_AUDIT` per clip and fails
  on root drift, a loop seam over 8 deg, a floating corpse or feet below the floor.
- Meshy rigged characters are 1.7 m tall; scale by height/1.7, never by mesh AABB. Zombie skins: shambler =
  shambler/farmer/hiker/grandma, runner = runner/jogger, soldier = soldier/forester, titan = titan/colossus; a new
  skin only needs the GLB in `godot/assets/models/` plus its name in the `skins` list. `gen_asset.py` reuses the
  task state in `assets/raw/<name>/` when that folder exists: a second variant needs a new asset name. Meshy statics come as
  ~1.9-unit boxes; `Weapons._fit_height` normalises them. Weapons/animals face +X / +Z, see rotations in code.
- Conifers (25 Sep 2026): two Meshy trees, `conifer_spruce` (Norway spruce) and `conifer_fir` (silver fir),
  prompts in `tools/assets.json`, the `_real` retextures (matte dark needles, brown bark) are the ones packed
  (`pack.mjs <name>_real --simplify 0.2 --simplify-error 0.03 --as <name>`; meshoptimizer stops at ~11k
  triangles because of the UV islands). `Trees.SPECIES` "fir" / "spruce_hd" carry `model`, height 19 / 20 m,
  a dark green `tint` and matte materials (specular 0, roughness 1 - the specular glints on the 14x scaled
  facets read as glass). `tools/conifer_zones.py` rewrites the species in `map.json` after `build_map.py`
  (deterministic): everything within 85 m of the Secret Night site = the Oberer Schorchen stand, 55 % of the
  deep forest (> 24 m from a track, > 60 m from the fire), 55 % of the aerial's spruce stands within 150 m,
  12 % scattered along the field-facing forest edge, never within 45 m of the fire and never within 6 m of a
  track edge (the crowns reach the ground and hung into the paths). LOD in `trees.gd`:
  within `MODEL_LOD` (100 m, per 48 m cell, toggled by `update_lod` from `update_shadows` - Godot's
  visibility ranges did not cull the MultiMesh cells) the GLB, beyond it a procedural spruce proxy at the
  same height; shadows always come from the card proxy (the GLB in four cascades cost 9 M shadow
  primitives). Cost on the plaza at 15:00: 64 -> 54 FPS. The birch (`tree_birch`, species "birch", 17 m,
  Meshy delivered it bare) carries a procedural beech card crown at every distance (`crown` /
  `crown_scale` 0.62 / `crown_detail` 0.45 in SPECIES) and uses the beech as far proxy; `conifer_zones.py`
  turns 14 % of the remaining beeches and oaks into birches (> 30 m from the fire, > 4 m from a track),
  91 of them; the base species travels along as `tree[5]` so reruns are idempotent. No measurable FPS
  cost (plaza 58, track 72). `--views` now prints VIEW_DRAW / VIEW_SHADOW
  (primitives, draw calls); `--no-model-trees`, `--model-shadows`, `--no-model-lod`, `--model-lod=<m>` isolate.
- Trees are otherwise procedural (`trees.gd`), nothing to download. Poly Haven clutter (ferns, moss, branches) is
  optional: `python tools/fetch_polyhaven.py` + `blender -b -P tools/tree_reduce.py` into `godot/assets/trees`
  (gitignored); `main.gd` skips it when absent.
- PBR ground textures in `godot/assets/textures/` (Poly Haven), leaf/grass sprites in `godot/assets/sprites/`.
- Audio: the user's sound library lives in `C:\Users\miche\Desktop\Developement\music` (not all of it fits the
  game). Selected clips are copied to `godot/assets/audio/{music,sfx}` with clean names; `sfx.gd` maps logical
  names to file variants (random pick) and falls back to procedural bursts, `music.gd` crossfades
  title / night / morning / combat / gameover plus a "horde" layer scaled by zombies alive. The pause after a
  cleared wave picks its track from the clock (`Music.intermission_track`): 05:00-17:00 plays "morning"
  (`survived_the_night.mp3`, user's song), otherwise the night loop. The round itself still opens on "night",
  so the daylight song is only ever heard once a wave is over; the intro keeps its own track.
  `TRACKS[..].file` names the mp3 when it differs from the logical track name. `--no-music` silences it.
  After adding files run `Godot.exe --headless --path godot --import`.
- Boss fights play one of the user's four boss songs (`music/boss_fight_1..4.mp3`, `Music.BOSS_TRACKS`,
  levelled by measured LUFS about 5 dB above combat since 24 Sep 2026) at random, never the same one twice in a row, and nothing else
  does. `Waves.is_boss_fight()` decides: every fifth wave from start to end, otherwise as long as a titan or
  field worm is alive or still queued (checked four times a second, sent to co-op clients as `wave[6]`).
  `Music.fight(bool)` swaps between the boss song and the combat loop, a cleared wave goes to the pause track
  as before. The songs do not loop (they stop dead at full volume), so a fight that outlasts one hands over
  to another 1.5 s before its end. `--suite=boss_music --smoke-test --no-intro --no-foliage` (29 checks).
- Walking through the maize is its own surface: `Sfx.STEP_SURFACES["corn"]` (bus `StepCorn`) plus the
  `_step_texture` case gives the per-step leaf swish, `Sfx.corn_bed()` the looping brush that
  `cornfield._update_rustle` fades with the player's speed while `cornfield.in_corn()` holds (silent on the
  cleared maze passages). `player._surface_step()` returns "corn" there. Checked in `--suite=range_steps`,
  which also dumps `artifacts/footsteps/corn_bed.wav` and `texture_corn.wav`.
- Bird wingbeats are not a sine: `tools/fetch_flap_library.py` downloads the animated birds of the three.js
  library (`examples/models/gltf/{Parrot,Stork}.glb`, morph flight cycles from ro.me, CC-BY), measures the
  shoulder / wrist / tip angles of every pose and bakes them into `godot/scripts/flap_cycle.gd` (32 samples per
  loop, radians, centred on the extended rest pose). `field_bird.gd` samples that - parrot for the raven, stork
  for the owl - and drives take-off burst, cruise, glide and landing from it; the curves are negated because the
  rig's roll axis points the other way. `--suite=cornfield --render-corn` renders `raven-flight` (top of the
  stroke) and `raven-downstroke`.
- Intro (`intro.gd`): after "Start game" a KONM Games card with `assets/audio/music/intro.mp3`, then the
  player wakes in dense fog at the south end of the Sennhofstrasse (136, 108) and is guided by a typewriter
  briefing and a HUD arrow along waypoints to the hut. Fog and intro music fade with the distance to the hut;
  reaching the Weg zur Hütte fires `road_reached` -> wave 1 (`waves.phase == "intro"` blocks the countdown
  until then). `--no-intro` skips it (autotest, benchmark and `--view=` skip automatically), `--intro-test`
  runs it headless-ish and saves `shots/intro_wake.png` / `intro_road.png`.

## Online lobby (EOS, 25 Sep 2026)
- The Multiplayer tab has two ways in: **Online lobby** (Epic Online Services: lobby + P2P with relay fallback,
  six-letter join code, anonymous Connect Device ID login, no Epic account, no port forwarding) and **Direct /
  LAN / Hamachi** (the unchanged ENet path on UDP 24567). Details: `docs/ONLINE_LOBBY.md`.
- Pieces: `godot/addons/epic-online-services-godot/` = EOSG 2.3.1 (GDExtension + EOS SDK 1.19.1.2 DLLs, MIT;
  the editor plugin is not enabled, the autoloads `EOSGRuntime`/`HPlatform`/`HAuth`/`HLobbies`/`HP2P` are listed
  by hand; the inner class `EOS.Achievements` is renamed `EOS.AchievementsApi` because RemZ's global class
  `Achievements` would otherwise break `eos.gd` - redo that after an addon update). `online_lobby.gd` (autoload
  `Online`) reaches everything EOS dynamically (`Engine.get_singleton("IEOS")`, `ClassDB.instantiate
  ("EOSGMultiplayerPeer")`, `load(eos.gd)`), so a missing runtime only disables the online tab.
  `net_session.gd`: `host_online` / `join_online` (async, `Error`), `transport` "enet" | "eos" | "offline",
  `online_pending`, `join_code`, app-level `_ping`/`_pong` for non-ENet peers, leaderboard rows sent one per RPC.
  Lobby attributes `CODE` / `VERSION` (`Online.version_tag()`) / `HOST`, bucket `remz-coop-1`.
- Hard facts: EOS P2P packets are at most 1170 bytes (EOSG header 6) - `SNAPSHOT_CHUNK` 900 fits, the
  `online_lobby` suite measures every RPC shape (largest 957) and fails above 1164; the lobby search index lags a
  fresh lobby by one to more than five seconds, `find_lobby` retries six times two seconds apart; **Godot never returns from `quit()` while a created EOS platform
  is alive** - `Online._exit_tree()` closes the peer and calls release + shutdown (`--suite=eos_exit_probe`).
- Credentials: only in the gitignored `.env` (root); `python tools/eos_config.py` writes the gitignored
  `godot/eos.cfg`, which the export preset packs (`check-game.ps1 -Mode ExportWindows` runs it first and then
  checks that `libeosg...release.dll`, `EOSSDK-Win64-Shipping.dll` and `xaudio2_9redist.dll` sit next to the exe).
  Never print or commit the secret. Portal: client "RemZ Windows", policy Peer2Peer, nothing else needed.
- Tests: `--suite=online_lobby --smoke-test --no-intro --no-music --no-foliage` (headless, offline, 43 checks),
  `--suite=online_live ...` (headless, internet, 21 checks against the real backend), `tools/test_online_coop.ps1`
  (two processes over EOS on one PC, the client with `--eos-fresh-device`; `-ForceRelay` pushes both through
  Epic's relay; `-Packed` uses `builds/windows/RemZ.exe` with `--host-online` / `--join-code=`),
  `RemZ.exe --headless -- --eos-check` on the packed build. Still untested: two different internet connections.

## Language (English default, German optional)
- Every player-facing text in the code is **English**; German is a translation the player picks under
  Settings > Language (`[game] language` in settings.cfg; never taken from the Windows locale). `lang.gd`
  (`class_name Lang`, autoload `Language`) installs the catalogues, `godot/locale/de.po` maps English msgid ->
  German msgstr (Swiss `ss`, real umlauts). Rules and glossary: `docs/LOCALIZATION.md`. In short: plain English
  literals on labels / buttons / Label3D / tooltips (Godot auto-translates them and follows a live switch),
  `Lang.t("... %d", [n])` for anything composed (a portable segment: the co-op client translates what the host
  built into its own language; string args such as weapon names are translated too, `Lang.raw(name)` keeps one),
  `Lang.text()` for draw_string and other sinks Godot does not translate, never `tr()`, never logic on displayed
  text. Shared keys that used to be German are English now: day phases Morning/Day/Evening/Night, mod slots
  Muzzle/Magazine/Bolt/Barrel, shop pages Trade/Quests/Rarities/..., gate names from `Map.GATE_NAMES`
  (map.json keeps the local names).
- New or changed text needs its German entry: a fragment `{"English": "Deutsch"}` + `python tools/i18n.py merge
  x.json`, then `python tools/i18n.py check` must report 0 problems (`review` lists English literals without an
  entry). `--suite=language --smoke-test --no-intro --no-music --no-foliage` sweeps every menu, shop page, the HUD,
  world labels, pause and game over: the English run fails on German left in the game, the same run with
  `--lang=de` on text without a German entry. Test runs are English unless `--lang=` is given (it also works for
  `--shot-ui` / `--views=`); a label holding a `Lang.t` segment is read in tests as `Lang.text(label.text)`.

## Testing
- `godot --headless --path godot --quit-after 150` catches script errors;
  `--script res://tests/run.gd -- --suite=compile_all` loads every script and test in ~3 s.
- Perimeter: `--suite=perimeter --smoke-test --no-intro --no-music` (headless, 17 checks: ring closed, roads only
  through gates, navmesh paths from every lane enter through a gate, sealed gates keep zombies outside and get
  attacked, a broken gate lets them in, Space vaults a built gate) and `--suite=perimeter_visual --no-intro` ->
  `shots/perimeter_*.png`. `--no-perimeter` builds the world without the ring (isolation).
- The expansion: `--suite=new_weapons --smoke-test --no-intro --no-music` (214 checks: every table
  a weapon has to appear in - DEFS with all 19 mandatory fields, ORDER, GOODS, model, mount data,
  muzzle profile, grips, sound, icon, equipping, firing, the muzzle inside the silhouette, and every
  mod combination) and `--suite=weapon_specials --smoke-test --no-intro --no-music` (36 checks on
  the mechanics themselves: overheating and venting including the weapon-switch exploit, the
  stowed barrel cooling and recharging, spin-up and spin-down without any key being held, the
  freeze building up and the brittle bonus, the graviton blast over a group and its independence
  from the damage multipliers, the flare igniting and lighting). `--render-weapons` in a windowed
  run adds `artifacts/new-weapons/<id>-{hip,ads,shot}.png` for judging grips and muzzle by eye.
- Weapon mods: `--suite=weapon_attachments --no-intro --no-music` (headless, 881 checks over every weapon x
  every compatible mod: bore axis, flush fit, calibre, no receiver or hand clipping, muzzle moved, grips and
  sight line unchanged, stacked loadout, co-op snapshot). Add `--render-mods` in a windowed run for
  `artifacts/weapon-mods/<weapon>-<mod>.png` (the joint, broadside, hands hidden) and `-ganz.png` (whole gun).
  `tests/weapon_mods.gd` stays the economy side. `weapon_effects.gd` (181 checks, windowed) now skips
  melee in its muzzle loop, so knife and hatchet no longer fail it.
- Coop load (Sep 2026): `--suite=coop_snapshot_cost --smoke-test --no-intro --no-music --no-foliage` (headless)
  times one host snapshot tick with four players and a full horde - build, var_to_bytes and DEFLATE run on the
  main thread ten times a second; `--suite=coop_host_load` (windowed, needs a renderer) measures the host's own
  frames while carrying that round. Sep 2026 on the dev PC: 2.1 ms per tick (40.7 kB raw, 6.8 kB packed) and
  143 FPS with the worst of 2143 frames at 13.1 ms.
- Zombie rigs: `--suite=zombie_motion` (headless, clip metrics of every skin, stride matching, idle, swing /
  death variants, flinch and scream fallbacks, runner gait switch, animation LOD, titan slam timing) and
  `--suite=zombie_anim_visual --no-intro --no-music` (windowed: `artifacts/zombies_v3/pose_<clip>.png`, one
  body per skin frozen at the telling moment of each clip, `headlook_on/off.png` for the head tracking, plus
  three frames of the walking row). After a
  model changes, rebake the shot volumes: `--suite=export_zombie_hit_shapes` then
  `python tools/bake_zombie_hit_shapes.py`, and run `--suite=horde_hit_precision` + `--suite=zombie_hitboxes`.
- Graphics profiles (`game_settings.gd`, measured 24 Sep 2026 with `--views` on the plaza, meadow and fork at
  1600x900): the high profile adds ultra-sampled SSAO / SSIL (half resolution), mipmap bias -0.3, a 256 px
  sky radiance and 8x anisotropy (balanced profile 8x too); every profile gets debanding and the fast one SMAA
  instead of FXAA. Together that costs about 2 % (8x anisotropy 1.2 %, the rest noise). Tried and thrown out
  because of their cost: an 8k sun shadow atlas (-40 %), full-resolution SSAO / SSIL (-8 %), blended shadow
  splits (-7 %), PCSS SOFT_HIGH (-3 %), a 24-bit shadow atlas (-3 %), 16x anisotropy (-2.5 %), 96^3 fog
  froxels (-1.5 %). `--gfx-off=ssaoultra,mip,aniso,radiance,debanding,smaa` switches single upgrades off.
- Horde checks: `Godot.exe --path godot --script res://tests/run.gd -- --suite=horde_visual --no-intro` (titan on the
  field, second skin, skin line, short titan walk -> `shots/horde_*.png`, prints HORDE_TITAN / HORDE_SKINS /
  HORDE_WALK) and `--suite=horde_bench --no-intro` (60 zombies: frozen / no shadows / anims paused / simulated FPS;
  Sep 2026 on the dev PC 148 -> 113 FPS, the horde itself is cheap). `Zombie.force_skin` pins a model for tests.
- `godot --path godot --resolution 1600x900 -- --autotest` starts the game, saves six screenshots to `shots/`
  (plaza, fountain view, fork, Weg zur Hütte, hut west face, hut north face) and quits; `--autotest --pathtest`
  instead spawns zombies on all four lanes and prints their positions after 40 s. Flags like `--no-shadows`,
  `--no-vfog`, `--no-foliage`, `--no-trees`, `--no-crowns`, `--no-trunks`, `--no-border` isolate features.
  `--views=x,z,yaw[,pitch[,hour]];...` renders several spots into `shots/view_N.png` and prints `VIEW_FPS` per
  spot (1.5 s sample, the cheapest way to benchmark a change). `--shot-ui` saves inventory, skills, pause tabs
  and the game-over screen as `shots/ui_*.png`; `--shot-menu` the start menu. `--difficulty=0..3` and
  `--quality=0..2` override the saved settings. Test runs (`--autotest`, `--smoke-test`, `--views`, `--shot-ui`)
  never write the high-score table. After regenerating `ground.png` run `Godot.exe --headless --path godot
  --import`, otherwise the game keeps the old texture. Godot.exe lives on the Desktop.
- Icons: `Godot.exe --path godot --script res://tests/render_item_icons.gd -- --weapons-only`
  renders only the weapons that have no icon yet (a full run overwrites every existing icon), then
  `--headless --import`. Running any suite with `--script` directly has no autoloads, so that file
  may only touch Weapons CONSTANTS - calling a Weapons function drags NetSession in and the run dies.
- Economy: points are the only currency. `main.KILL_VALUE` (0.6) scales the kill bounty, the wave bonus is
  20 + 6 n, quest "arrival" pays 20; the HUD shows the balance bottom-left in gold with a +/- delta popup.
  "Play again" / "New round" rebuild the scene and start the next round directly (`NetSession.restart_pending`
  offline, `_auto_start` for the coop host); `--suite=menu_flow --smoke-test --no-intro --no-music --no-foliage`
  checks zombie damage, death -> Play again, pause -> main menu and the coop restart (11 checks, ~45 s).
- Loading screen (`boot_screen.gd`): main builds the world in one long `_ready` and `BootScreen.step()` force-draws
  a frame after every build step. Controls record their draw commands only on the next idle frame, which never
  comes inside `_ready`, so the screen paints with RenderingServer calls on its own canvas item. As Labels it
  stayed empty at the very first start and every step showed the half-built world, blown out white (sky radiance
  not baked yet). Above the title stands the crest with the zombie deer, `assets/ui/remz_crest.png`, cut out of
  `godot/icon.png` by `python tools/build_crest.py [--preview]` (traced rim, transparent backdrop, soft red glow,
  827 x 959 px, imported with mipmaps); `BootScreen.crest_rect` makes it as tall as the window allows but never
  more than 1.1x its own pixels on the physical screen. `--suite=start_exposure --no-music` (windowed, no
  --smoke-test, 14 checks) reads back every frame from the first loading step through menu, intro and pause ->
  main menu and fails on a blown-out frame, a loading-screen frame whose outer strips are not the dark ink, or a
  loading screen without the crest. `frame_post_draw` reports the previous frame.
- Cheat menu (Ctrl+Shift+D, `cheat_menu.gd`): +1000 R, skip wave, minimap reveals and every weapon of
  `Weapons.ORDER` with a full magazine (mods included) and the reserve at `reserve_limit` (`fill_weapon`, also
  cools a plasma barrel); the chosen weapon goes straight into the hands, "Alle Waffen" fills all of them.
  Host / solo only, like the other cheats. `--suite=cheat_menu --smoke-test --no-intro --no-music --no-foliage`
  (27 checks).
- `tests/range_steps.gd` (headless, `-- --smoke-test --no-intro --no-music`) checks long-range hits and the
  per-surface footsteps (`Sfx.footstep`: low-pass bus per surface + procedural texture layer; asphalt has zero
  cover weight in `ground.png`, so "all channels < 0.3" means hard ground) and dumps the step textures to
  `artifacts/footsteps/*.wav`. Weapon `range` is only the start of a 55 % damage falloff; the hit ray is 600 m.
- Other agents (a Codex/VS Code session, earlier a second Claude session) edit this working tree concurrently:
  check `git status` and mtimes before editing, patch instead of overwrite, stage only your own files.
- Pitfalls learned: SDFGI leaks through leaf cards and burns them white (keep it off, use SSIL). Flat road
  ribbons must not receive shadows, and their triangle winding must be counter-clockwise seen from above or
  they render black (back-face normals). Large Bash heredocs with Python break on Git Bash;
  write patch scripts as files instead. Never build a StandardMaterial3D or ParticleProcessMaterial per
  shot / effect: when the last instance with a feature set is freed, Godot frees its generated shader and
  the next shot compiles it again (the flare pistol stalled 30-50 ms on every shot that way). Keep one shared
  instance (`WeaponSpecials.star_mesh`, `ElementalEffects.tracer_material`, `Grenade._explosion_parts`) and
  warm it in `combat_warmup.gd`; `--suite=flare_hitch` (windowed, 18 checks) counts the pipelines per shot.

## Repo hygiene
- Commit locally with the Co-Authored-By line; push only when asked. The git remote URL currently embeds a
  personal access token, the user should move to a credential manager.
