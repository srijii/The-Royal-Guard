# In Search of the Ring

A 2D story-action game built with **Godot 4.5**.  
You play as a royal guard tasked with protecting the princess and the royal ring, surviving the night attack, and recovering enough keys to reach the final boss.

> In-game branding also uses the title **“Royal Guard”** in the main menu.

## Highlights

- Story-driven intro with dialogue and quest progression
- Multi-stage gameplay across palace, outer world, and final boss scenes
- Combat against skeleton and warden/wizard enemies
- Health, energy, strength, and potion systems
- Save/continue support
- Rebindable controls and optional mobile controls

## Game Flow

1. **Main menu** (`scene/main_menu.tscn`)
2. **Palace world** (`scene/world.tscn`)
   - Learn the setup from the princess
   - Find the torch and read the map
   - Defend the princess from skeleton thieves at night
3. **Outer world** (`scene/outerworld.tscn`)
   - Defeat wizards to collect keys
   - Open the gate and continue
4. **Final boss** (`scene/final boss.tscn`)
   - Win the encounter and collect the princess ring

## Default Controls

Core movement/actions:

- **WASD / Arrow keys**: Move
- **Ctrl**: Attack
- **Shift**: Sprint
- **M (hold)**: Zoom out map view
- **L**: Toggle lamp (after unlocked)
- **E**: Interact with nearby quest items
- **Esc**: Pause / resume
- **H**: Show keybind help

Potions:

- **Space**: Regeneration
- **J**: Strength potion
- **K**: Energy drink

You can rebind keys from **Settings** in the main menu.

## Run the Project

### Prerequisites

- Godot **4.5** (Forward Plus renderer)

### Open in editor

1. Launch Godot 4.5
2. Import this folder:
   - `.../in-search-of-the-ring/project.godot`
3. Run the project (main scene: `scene/main_menu.tscn`)

### Export

- An export preset for **Windows Desktop** exists in `export_presets.cfg`.

## Saves and Local Config

The game stores runtime files in Godot’s `user://` directory:

- `savegame.json` (game progress)
- `keybinds.cfg` (custom key bindings)
- `options.cfg` (settings such as mobile controls)

## Project Structure

- `scene/` – Godot scenes (`.tscn`)
- `script/` – gameplay and UI scripts (`.gd`)
- `script/global/` – autoloaded globals
- `art/`, `tileset/`, `fonts/`, `sounds/`, `imgg/` – assets

## Documentation

- [Gameplay Guide](docs/gameplay-guide.md)
- [Development Notes](docs/development.md)

