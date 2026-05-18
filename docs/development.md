# Development Notes

## Tech Stack

- Engine: **Godot 4.5**
- Language: **GDScript**
- Main project file: `project.godot`

## Core Scenes

- `scene/main_menu.tscn` – entry point and settings
- `scene/world.tscn` – palace/intro quest and night defense
- `scene/outerworld.tscn` – key collection and door progression
- `scene/final boss.tscn` – final encounter and ending
- `scene/credits.tscn` – credits screen

## Key Scripts

- `script/main_menu.gd` – menu actions, settings popup, key rebinding
- `script/player.gd` – movement, combat, potion usage, mobile controls, player stats
- `script/world.gd` – quest state, interactions, save/load, night event flow
- `script/outerworld.gd` – enemy/key gate progression and transition to final boss
- `script/final_boss.gd` – boss arena setup, death/respawn, ending flow
- `script/npc.gd` – princess dialogue/story and behavior logic
- `script/global/player_stats.gd` – global stat helpers
- `script/global/helpers.gd` – global helper utilities

## Input & Rebinding

Default gameplay actions include:

- Movement (`ui_up/down/left/right`)
- `attack`, `sprint`
- `hold_map_zoom`
- `use_health_potion`, `use_strength_potion`, `use_energy_drink`

Runtime keybinds and options are stored under `user://`:

- `keybinds.cfg`
- `options.cfg`

## Save Data

- Save file path: `user://savegame.json`
- Continue button in main menu is enabled only when save exists.

## Assets

- `art/` – sprites and images
- `tileset/` – tile resources
- `sounds/` – audio
- `fonts/` – fonts
- `imgg/` – additional image assets

## Export

- Windows Desktop export preset is configured in `export_presets.cfg`.

## Local Validation

This repository does not include a dedicated test/lint pipeline in-tree.  
To sanity-check locally, open the project in Godot 4.5 and run from the editor.

