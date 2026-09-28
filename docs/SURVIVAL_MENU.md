# Survival menu

The main-menu briefing describes REMZ as a solo and co-op zombie survival game:
choose an available campaign region, survive 25 waves, complete quests, upgrade
equipment and develop class talents. Region availability remains controlled by
`Campaign.REGIONS`; regions under construction are still unavailable.

The main menu has no Heitersberg subtitle. Briefing, difficulty descriptions and
controls use general survival language. Map-specific introductions, objectives
and warnings remain attached to their actual gameplay.

Every start-menu detail has a visible **Back to main menu** button in its header.
Click it, press **Esc**, or click the selected tab again to restore the compact main
menu and character panel without reloading the scene or leaving a co-op lobby.
Character dialogs close before the underlying menu. Map selection and the
pause menu retain their existing navigation.

Validation: `--suite=survival_menu --smoke-test --no-intro --no-music` with a
windowed renderer checks actual mouse/key input in English and German, 720p
reachability, modal priority and pause navigation. Screenshots are written to
`artifacts/survival-menu/`. German strings live in `tools/i18n_survival_menu.json`
and `godot/locale/de.po`.
