# Assassin Teleport

From Assassin level 15, select one additional active ability in **Class skills** before a round. All six passive talent tiers remain available. Existing profiles retain XP and passive choices and start with no Teleport selected.

| Mode | Activation | Range | Cooldown |
| --- | --- | --- | --- |
| Forward | V | Up to 8 m along horizontal facing; stops before walls | 12 s |
| Map | V, then left-click a point on the local map | 40 m | 30 s |

Selecting Master Assassin at level 30 halves these cooldowns: Forward takes 6 seconds, Map takes 15 seconds.

The map keeps the round running. Escape, right-click, V, or Cancel closes it without spending cooldown. Blocked, occupied, disconnected, steep and out-of-bounds landings are rejected. Field-trial boundaries remain enforced. Teleport is unavailable while downed, dead, spectating, mounted, piloting a drone or during the intro. The HUD shows the chosen mode and remaining cooldown.

In co-op the host validates the frozen loadout, range, cooldown, navigation and capsule clearance. Snapshots carry the relocation serial and cooldown. Client poses must acknowledge the current serial, so in-flight movement from before a teleport cannot undo it. Protocol 5 / `remz-dev-20260928-assassin-teleport` requires matching builds.

Validation: `assassin_teleport`, `class_system`, `movement_sync`, `class_integration`, `class_coop`, `teleport_visual` and `teleport_input` through `tests/run.gd`. The last two suites require a windowed renderer; headless Godot cannot capture the mouse. The isolated teleport physics suite never touches player saves.

Menu wordmark: `assets/ui/remz_logo_v3.png`, with alpha and mipmaps for small display sizes.
