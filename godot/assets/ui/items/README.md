# Item icons

PNG previews are rendered from the game's existing weapon, mushroom, supply, barricade and tower models. SVG symbols cover training, quests, keys and finish swatches. They use the same item IDs as `ItemIcons` and are shared across the merchant UI, inventory and construction UI.

Regenerate model previews from the repository root with:

```powershell
& 'C:/Users/miche/Desktop/Godot.exe' --path godot --script res://tests/run.gd -- --suite=render_item_icons
& 'C:/Users/miche/Desktop/Godot.exe' --headless --editor --path godot --import --quit
```

Visual review: `--script res://tests/run.gd -- --suite=progression_visual --icons-only --no-intro --no-music`. Screenshots go to `artifacts/progression/icons-*.png`.

Icons are static cached textures. Menus do not render extra 3D viewports during gameplay. Their controls ignore mouse input so the underlying inventory and purchase buttons stay clickable.
