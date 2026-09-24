# Defense and field titans

**E** builds or reinforces right at a barricade line; if the line is damaged, E repairs it. A whole line costs 50 Rem Dollars, a repair 25. Three tiers with 300 / 600 / 900 hit points; reinforcing also reduces the damage the line takes. **V** points you to defense advice at Mechanic. Traders, the introduction and quests: [Progression](PROGRESSION.md).

Zombies attack a built line when it blocks their way to the hut. They keep their breach target while they step aside. Enemies from the four approach directions take the matching fortified approach into account. Once it is destroyed, they continue the chase. A line protects its approach; enemies that are already behind it remain dangerous.

## Gun turrets

- **T** opens the tower build menu. **R / Mouse wheel** rotates the build preview, **Shift+R** rotates it back, **E** confirms, **T / Esc** cancels.
- Types and build prices: **Sentinel 120 R**, **Flamethrower 260 R**, **Mortar 380 R**, **Heavy MG 450 R**, **Tesla Coil 600 R**. No more than six towers per team.
- **E at a tower:** mount it, aim with the mouse, **Left click** fires, **Hold right click** zooms and reduces the angular spread by 75%, **E** dismounts.
- **R at an unoccupied tower:** re-align it. **F:** repair for 35 R. Upgrading and dismantling at **Mechanic → Towers**; prices scale with the type.
- Base ranges: Sentinel 26 m, Flamethrower 14 m, Mortar 60 m, Heavy MG 44 m, Tesla Coil 22 m; each upgrade tier adds 6 m. The ground marker and the target display help you judge range and obstacles.
- Unmanned towers fire automatically within a 160° sector; operated manually, they can fire all around. Sustained fire leads to overheating. Walls and terrain stop shots; team members take no damage from towers.
- Zombies and titans can destroy towers. Behind a barricade, towers are better protected. On the minimap they appear as blue squares.

## Roof turrets on the forest hut

- At the forest hut, **T** offers six roof slots (three on each side of the roof) next to ground placement; the first free slot is preselected. Choose the weapon, **R / Mouse wheel** turns the field of fire, **E** builds, **T / Esc** cancels at no cost.
- Same five types, prices and unlock waves as on the ground. Roof and ground towers share the limit of six per team.
- Roof turrets always fire automatically in their 160° sector; they cannot be mounted. From the edge of the roof they also hit zombies standing right at the hut wall (the Flamethrower from about 1.2 m). Zombies and titans cannot reach them.
- Pick an occupied slot in the same menu to repair it (35 R) or re-align it. Upgrading and dismantling at **Mechanic → Towers**.

## Drone control center

The console stands upstairs in the forest hut; you need the hut key. **E** at the station, pick a drone, then **Ready to fly**.

| Drone | From wave | Hull | Damage per shot | Shots/s | Speed | Range |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Kestrel Scout | 5 | 100 | 24 | 5.6 | 9 m/s | 65 m |
| Viper Gunship | 10 | 180 | 42 | 8.3 | 11 m/s | 85 m |
| Tempest Assault | 15 | 280 | 62 | 11.8 | 12 m/s | 110 m |

- **WASD** flies relative to where you look, **Mouse** aims, **Space / Ctrl** climbs and descends, **Left click** fires, **R / Esc** recalls the drone. The flight ceiling is 45 m above the ground, and the drone cannot leave the map.
- Your body stays at the station and can be attacked; your own weapons and grenades are locked during the flight. Sustained fire overheats the drone gun. Bumping into obstacles scrapes the hull a little; zombie strikes and titan slams hit hard.
- Each model flies once per team at a time, and each player flies one drone. Launching costs nothing; after a recall the drone is ready again in 10 s, after it was destroyed in 30 s.
- Mechanic's quest line **Drone Operations** starts with wave 5, see [Progression](PROGRESSION.md).

## Field titans

The first titan, about **27 m tall, appears in wave 6**, then in every third wave, except worm waves (every fourth wave from wave 12) and boss waves (every fifth wave): field titans therefore come in waves 6, 9, 18, 21, 27, 33, 39 and so on. Up to wave 17 there is one, from wave 18 there are two and from wave 36 three (first in wave 39), each at a separate spot on the fields. From wave 8, the remaining waves without a field titan, worm or boss wave bring smaller titans: the Hunter Titan (8 m) from wave 8, the Siege Titan (14 m) from wave 11 and the Ash Titan (19 m) from wave 13, one per wave up to wave 23 and two after that. The existing brute waves remain. Titans come across the open southern fields, with their own rigged model, heavy footsteps and a boss health bar. The values below apply to the field titan; the smaller titans have their own warning times, radii and damage.

Before the area attack, an orange marker appears that follows the terrain. It stays at the announced point of impact; you can run out of it within the 2.4-second warning time. The impact damages players and defenses within a radius of 8.5 m, followed by a recovery phase. Walls limit the impact and shield you from the shock wave. Below 55% health, the titan gets faster. Bullets and melee strikes cannot stun it permanently. Difficulty, later waves and the number of players affect its strength.

On **Normal, a titan impact deals 70 damage to players**, before any protection from mushrooms. Against barricades and doors it deals **230**, against gun turrets **240** and against the hut **440 base damage**; reinforcements still reduce the damage taken. The difficulty scales these values: before protection, players take 49 damage on Easy, 91 on Hard and 119 on Nightmare. From wave 7, all titan damage also rises by 1.2% per wave, up to +40% from wave 40. Without health upgrades or protection (100 health), you survive a direct hit on Easy and Normal; on Hard it is fatal from wave 18, on Nightmare already with the first titan.

## Roars and ground tremors

Titans have eight sound files of their own: three deep, rough roars, a short attack roar, a death cry, two heavy footsteps and a ground slam. The roars layer the existing zombie recordings with deep throat resonances and breathing. On top of that come four arrival cries: when a titan appears, one of them can be heard across the whole map. Titans roar especially clearly when they appear and when they drop below 55% health. While they approach, further roars follow every 20–30 seconds, with long quiet stretches in between.

Depending on the action, roars can be heard up to about 220–250 m away, the arrival cry across the whole map, and they come from the titan's head in 3D space. The music briefly ducks during a roar. Footsteps carry a shorter distance; distance dampens the treble and the volume. A dedicated compressor and limiter keep the mix under control when several titans appear at once.

Footsteps, stomps and the falling body cause short, softly fading ground tremors. Their strength decreases with distance. On death, the heavy body only hits the ground after the death cry. There is no permanent camera shake. Under **Settings → Titan ground tremors** you can reduce their strength or turn them off completely; the volume follows the normal volume slider.

In co-op, the host sends these events to all teammates as well. Everyone hears the source from their own position and feels a tremor of matching strength. Roars or slams that already happened are not replayed for players who join later.

## Co-op and testing

The host checks building sites, orientation, Rem Dollars, distance to traders, repairs, damage and boss attacks. Towers, upgrades, boss health, warning areas and impacts are synchronized; players who join late receive the current state. In co-op, the world keeps running during trader conversations; in solo, the conversation pauses the game. Placing and rotating remain actions in the running world.

All players need the same new build. The version check rejects old co-op versions.

Checks:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode Defence
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode TitanHorror
powershell -ExecutionPolicy Bypass -File tools/check-game.ps1 -Mode TitanMix
powershell -ExecutionPolicy Bypass -File tools/test_multiplayer.ps1
```

Among other things, the game tests check real barricade attacks, tower hits and cover, build costs, upgrade tiers, boss warning/dodging/death and the real route from the field to the approach. The co-op test starts four independent Godot processes. Screenshots of towers, the build preview and titans are in `artifacts/defence/`.
