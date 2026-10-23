# Harbourlife pack: start here

Everything for Harbourlife so far:
- core systems, the pizza shop, vehicles and the excavator, and retail
- the Phase 5 food businesses
- **Harbour Mall**: escalators, lifts, automatic doors, 16 stores, food court, mall jobs, NPC shoppers, and a car park
- the new **inventory menu** and **GTA-style phone**

None of it has been tested in Roblox Studio yet, so check the Output window when you first press Play.

## What's in the folder

| Path | What it is |
|---|---|
| `build/Harbourlife.rbxlx` | A Roblox place with every script already in it. Open it in Studio, or copy its scripts into your town |
| `src/` | The same scripts as plain text files (used by Rojo or Claude Code) |
| `docs/ClaudeInstallGuide.md` | Step-by-step instructions for **Claude Code** to install everything into your town in Studio |
| `docs/MallSetup.md` | How the mall works and how to place it |
| `docs/PizzaBusinessSetup.md` | Part names for the pizza shop, food businesses, vehicles and shops |
| `docs/Harbourlife*.md` | Build progress, known issues, asset list, scope notes |
| `CLAUDE.md` | Read automatically by Claude Code; points it to the install guide |
| `tools/build_place.py` | Rebuilds `build/Harbourlife.rbxlx` from `src/` (`python tools/build_place.py`) |

## Option A: let Claude Code do it (recommended)

1. Unzip this folder somewhere on your PC.
2. Open your town place in Roblox Studio.
3. In a terminal inside this folder, connect Claude Code to Studio:
   ```
   claude mcp add --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"
   ```
4. Start Claude Code in this folder (`claude`) and say: **"Follow docs/ClaudeInstallGuide.md"**.
   It will:
   - back up your place
   - copy the scripts in
   - help you mark the mall and car park areas
   - build the mall
   - go through the test checklist with you

## Option B: do it by hand

1. Open `build/Harbourlife.rbxlx` in Studio. In Explorer, copy:
   - `ReplicatedStorage > Shared`
   - `ServerScriptService > Systems` and `ServerScriptService > Main`
   - everything in `StarterPlayer > StarterPlayerScripts`

   Paste them into the same places in your town (replace the old copies).
2. In your town, add two anchored, flat Parts:
   - **`MallSite`** over the area where the mall goes (2 × 2 blocks)
   - **`CarParkSite`** over the car park area (1 × 2 blocks beside it), leaving the road between them

   Clear the roads, trees and buildings under them first.
3. Press **Play**. The mall builds itself.
   To keep it as editable parts instead, run this in the Command Bar and save:
   ```lua
   require(game.ServerScriptService.Systems.MallBuilder).Build(true)
   ```
4. In `ServerScriptService > Systems > TestWorld`, set `Enabled = false` if you don't want the dev test pads near the
   middle of your map.

## Controls

| Key | Does |
|---|---|
| **P** / 📱 button | Phone: Bank, Jobs, Bag, GPS, Messages, Stats, Garage, Settings |
| **I** / 🎒 button | Inventory, grouped by category, with Skills & Stats |
| **E** | Use prompts (shops, stations, ATMs, jobs, lifts…) |
| **Backspace** | Back on the phone |

If anything errors, copy the red text from the Output window and send it to Claude.
