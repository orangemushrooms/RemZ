# Discovery sites — 6 October 2026

Outposts use the shipped workbench, medical kit, ammunition chest and stacked sandbag
models. Transmitters reuse the shipped siren assembly with a metal antenna and a small
physical number. Caches use the textured ammunition chest on both maps. No new Meshy
generation, credits, downloads or third-party asset dependencies were needed.

Discovery sites no longer have grey placeholder blocks, glowing poles or floating
billboard titles. Outposts remain on the minimap; caches and transmitters do not.
Active delivery destinations and other mission markers retain their existing behaviour.
Small flattened patches make the props visible in Planes crops. Changing the run layout
restores the previous vegetation before applying the new patches. Props follow terrain;
snapshot position changes rebuild their ground placement. Collected props disable their
colliders as well as their visuals.

The active outpost HUD shows remaining hold time and health below the compass. It
explains when nobody is holding the area and when attackers remain after the hold time.
Host snapshots supply occupancy to clients, so a distant teammate sees the real state.
The status disappears after completion and while menus are open. The existing 35-second
capture duration, rewards and supply replenishment rules are unchanged.

## Validation

- `compile_all`: 383 scripts, no broken scripts.
- `i18n.py check --quiet`: 2633 entries, zero problems.
- `expedition`: 442 assertions, zero failures; Forest and Planes progression, sites,
  checkpoints, structures, rewards and finales.
- `expedition_sites --render --lang de`: 45 assertions, zero failures.
- `expedition_sites --render --lang en`: 45 assertions, zero failures; final geometry.
- `test_expansion_coop.py planes`: real ENet host/client, 29 + 16 assertions, zero
  failures, including remote countdown/occupancy and hidden discovery markers.
- Rendered screenshots inspected for all three site types. Test saves and profiles are
  isolated under `artifacts/expansion-tests`; normal player saves are not touched.
- Windows release export: passed, no script errors. Native release startup reached
  the readiness marker on Forest and Planes.
- `test_expansion_pack.py`: 28 Forest + 35 Planes assertions against the exported PCK,
  zero failures. Includes textured site assets, minimap filtering, actual physics rays
  against the crate before/after collection, and the live German outpost countdown.
- EOS release audit: configured runtime present; no unrelated secrets in the package.

The local Windows sandbox reports its existing root-certificate-store warning.
The runners treat other engine/script errors as failures. These checks establish the
tested behaviours; they are not a guarantee against every possible gameplay defect.
