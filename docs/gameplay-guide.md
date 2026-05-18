# Gameplay Guide

## Objective Summary

Your main objective is to protect the princess and secure the royal ring through three phases:

1. **Palace preparation** – complete early quests and survive the night attack.
2. **Outer world progression** – collect wizard keys and unlock the gate.
3. **Final boss** – complete the last encounter and capture the ring.

## Phase 1: Palace (`scene/world.tscn`)

- Follow the princess dialogue/tutorial.
- Collect required exploration items:
  - **Torch**
  - **Map**
- Return before midnight trigger.
- Defend the princess during skeleton assault.

### Helpful keys in this phase

- `E` for interactions (torch/map and other interactables)
- `L` to toggle lamp (once unlocked)
- `H` for keybind help overlay

## Phase 2: Outer World (`scene/outerworld.tscn`)

- Fight enemies and gather resources.
- Defeat wizards to collect **Wizard Keys**.
- Reach **3 keys** to open the gate.
- Enter the destination door to transition to final boss.

UI shows:

- Player hearts
- Energy and strength bars
- Potion inventory
- Current wizard key count
- Quest guidance text

## Phase 3: Final Boss (`scene/final boss.tscn`)

- Fight while managing health and combat timing.
- Respawn option is available on death.
- On success, the ending sequence plays after ring capture.

## Combat & Resources

- **Attack**: `Ctrl`
- **Sprint**: `Shift` (energy system applies outside specific scripted overrides)
- **Potions**:
  - Regeneration (`Space`)
  - Strength (`J`)
  - Energy (`K`)

Use potions based on need:

- Regeneration for sustained fights
- Strength for higher damage windows
- Energy drink to recover sprint/combat mobility resource

## Save/Continue

- Continue is available from the main menu when a save exists.
- Save data is persisted in `user://savegame.json`.

