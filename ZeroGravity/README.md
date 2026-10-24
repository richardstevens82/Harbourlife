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
   asteroids, wrecks and lobby) from code. That takes about a second. In the menu, press **DEPLOY**.
4. Every match has 20 combatants, and the last one standing wins. Queued players deploy first and
   bots fill every empty seat, so with just you online there are 19 bots, and with nobody queued
   it's 20 bots. To test with real players too, use **Test → Clients and Servers**. Each real player
   replaces a bot from the next match. Bot settings (count, skill, `[BOT]` name tag) are in
   `Config.Bots`.
5. You're queued as soon as you join. The countdown at the top of the screen runs for 30 seconds,
   then everyone deploys. Lobby practice can't hurt other pilots or bots; damage only counts in a
   match. If every real player is eliminated, the storm collapses so the bots finish within about
   half a minute, and the next countdown starts.

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
| Air roll left / right (dodge, uses energy) | Q / E | |
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
                                  HazardService, LagCompensation, NavGraph, BotService,
                                  MatchService
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.luau        bootstrap + server-message routing
    Controllers/                  Input, Camera, Movement (zero-g), Combat, CharacterAnimator
                                  (procedural flying/aiming/rolling poses, hand IK on the gun),
                                  Effects (VFX/audio, storm sphere, planet), HUD, Menu, UIKit,
                                  ClientState
  StarterPlayer/StarterCharacterScripts/
    Animate.client.luau           empty: replaces Roblox's walk/fall animations
    Health.server.luau            empty: replaces Roblox's health regeneration
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
python3 tools/gen_roblox_api.py     # refresh tests/api/roblox_api.luau from Roblox's API dump
python3 tools/render_blockout.py    # docs/blockout/*.png (needs matplotlib)
python3 tools/render_poses.py       # docs/animation/pose_sheet.png: the real animator on an R15 rig
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions=@roblox=globalTypes.d.luau --no-strict-dm-types src   # type check
```

`tests/mock.luau` is a small Roblox API mock: real CFrame maths, instances, tags, a scheduler with a
simulated clock, raycasts and terrain. It checks every property and member access against Roblox's
real API tables (`tests/api/roblox_api.luau`), so a name Roblox would reject fails the tests. It's enough to run the real builders, the server services and
the client movement and UI code without Studio. See `BUILD_STATUS.md` for what that does and doesn't
prove.
