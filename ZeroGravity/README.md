# ZERO GRAVITY: LAST ORBIT

A zero-gravity PvP battle royale for Roblox. Players deploy into an orbital battlefield: a modular
space station, a 550-stud exploration ship, an asteroid mining field and derelict wrecks. They loot,
manage oxygen, and fight in full 3D while a spherical radiation storm closes in. The last player in
orbit wins.

This folder is a self-contained Roblox project, separate from the Harbourlife game in the rest of
the repository.

## Open it in Roblox Studio

**Option A: place file (no extra tools needed).**
1. Run `python3 tools/build_place.py`. This writes `build/ZeroGravity.rbxlx`. A prebuilt copy is committed.
2. Open `build/ZeroGravity.rbxlx` in Roblox Studio.
3. Press **Play**. When the server starts, it generates the whole environment (station, ship,
   asteroids, wrecks and lobby) from code. That takes about a second.
4. Matches are 20 combatants. Bots fill every empty slot, so with just you online there are 19 bots.
   One queued player is enough to start. To test with real players too, use **Test → Clients and
   Servers**; each real player replaces a bot from the next match. Bot settings (count, skill,
   `[BOT]` name tag) are in `Config.Bots`.

**Option B: Rojo.** `default.project.json` maps the same layout. Run `rojo serve` and connect from
Studio.

**For saving progress in a published place:** enable *Game Settings → Security → Enable Studio
Access to API Services*. Without it, the game runs on temporary data and the menu warns that
progress isn't saving.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Thrust forward / back, strafe | W S / A D (relative to the camera) | Left stick |
| Move up / down | Space / Left Ctrl | A / B |
| Boost (uses energy) | Left Shift | L3 |
| Stabilise / brake to a stop | X | X |
| Look | Mouse | Right stick |
| Fire / aim | Left / right mouse | R2 / L2 |
| Reload, melee | R, V | Y, R3 |
| Weapons | 1 2 3, mouse wheel | L1 |
| Use utility (tether / pulse charge) | G | R1 |
| Switch utility | Z | D-pad up |
| Medical, shield cell, O2 canister | 4, 5, 6 | D-pad left/right/down |
| Interact (search, pick up, airlocks, O2 stations) | F | (prompt button) |
| Inventory, tactical map, menu | Tab, N, M | Select, -, Start |
| Spectate next / previous, leave spectate | E / Q, Backspace | |

Keyboard bindings can be changed in **Menu → Settings**. The change lasts for the current session
only.

## How the project is organised

```
src/
  ReplicatedStorage/Shared/       Config, weapon/item/loot/cosmetic/loadout definitions,
                                  ZoneMath (pure), WeaponModels, Remotes (5 RemoteEvents)
  ServerScriptService/
    Main.server.luau              bootstrap: builds the world, starts every service (isolated)
    Builders/                     procedural environment: Kit (construction kit), Station, Ship,
                                  AsteroidField, Debris, Lobby, Backdrop (lighting)
    Services/                     WorldBuilder, Roster, SecurityService, CharacterService,
                                  DataService, InventoryService, CombatService, LootService,
                                  OxygenService, SafeZoneService, EquipmentService,
                                  HazardService, NavGraph, BotService, MatchService
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.luau        bootstrap + server-message routing
    Controllers/                  Input, Camera, Movement (zero-g), Combat, Effects (VFX/audio,
                                  storm sphere, planet), HUD, Menu, UIKit, ClientState
tests/                            headless Roblox mock + specs (run with tools below)
tools/                            build_place.py (rbxlx + sourcemap), render_blockout.py
docs/blockout/                    rendered plan/elevation views of the generated map
```

The whole map is built at runtime from code. There are no free models and no third-party scripts.
Gameplay systems find what they need through CollectionService tags placed by the builders:
`LootSpot`, `DeployPoint`, `FinalZone`, `OxygenStation`, `Pressurized`, `Airlock`,
`ElectricHazard`, `ReactorHazard`, `ExplosiveBarrel`, `Breachable` and `SmokeVolume`. To add
content, call the Kit functions and drop markers.

## Tests and tooling

```
python3 tools/build_place.py        # build/ZeroGravity.rbxlx + sourcemap.json
python3 tests/run.py                # headless tests incl. a full simulated 20-combatant bot match (needs `luau`)
python3 tools/render_blockout.py    # docs/blockout/*.png (needs matplotlib)
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions=@roblox=globalTypes.d.luau --no-strict-dm-types src   # type check
```

`tests/mock.luau` is a small Roblox API mock: real CFrame maths, instances, tags, a scheduler with a
simulated clock, raycasts and terrain. It's enough to run the real builders, the server services and
the client movement and UI code without Studio. See `BUILD_STATUS.md` for what that does and doesn't
prove.
