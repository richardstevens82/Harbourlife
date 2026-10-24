# BUILD_STATUS — ZERO GRAVITY: LAST ORBIT

_Last updated: 2026-10-24_

## Read this first: what "tested" means here

This build was written in a cloud container that has **no Roblox Studio and no Roblox client**.
Every claim below falls into one of three levels, and they are kept separate:

- **Implemented**: the code exists, compiles, and passes the Luau type checker (luau-lsp with
  Roblox API definitions) with no errors in non-strict mode.
- **Tested headless**: exercised by `tests/run.py`. That suite runs the real source files against
  `tests/mock.luau`, a hand-written Roblox API mock with real CFrame maths, instances, tags,
  raycasts, terrain fills, and a scheduler with a simulated clock. It proves the logic, geometry and
  wiring are sound. It does **not** prove how things behave in Roblox's physics engine, renderer,
  networking or audio.
- **Unverified in Studio**: nothing has been run inside Roblox yet. Physics feel, visuals, lighting,
  sounds, UI layout and real multi-client networking still need a Studio playtest. See *Required
  manual actions*.

## Stages

| Stage | Status |
|---|---|
| A. Inspect project, architecture | Done. The repo held only the unrelated Harbourlife game, so this is a separate project in `ZeroGravity/`. |
| B. Environment blockout | Done: station (hub + 6 branches + habitat ring), exploration ship, asteroid field, derelicts/debris, lobby, planet backdrop |
| C. Inspect & correct blockout | Done (automated). Passability, embedding, spacing and sealing checks plus rendered plans in `docs/blockout/`. Fixes listed below. |
| D. Detail environment | First pass: modular kit with furniture, consoles, lockers, cargo, lights, signage, windows, solar arrays, antennae, hull detail. Not a final art pass. |
| E. Zero-g movement | Implemented + tested headless (integrator). Feel unverified in Studio. |
| E2. Bots (fill to 20) | Implemented + tested headless (full simulated 19-bot match). Unverified against real collisions. |
| F. Match lifecycle | Implemented + tested headless (two full simulated matches, including a disconnect) |
| G. Weapons & server-authoritative combat | Implemented + tested headless (validation, damage, shields, reload, kills) |
| H. Loot, inventory, oxygen, equipment | Implemented + tested headless |
| I. Safe zone & special mechanics | Implemented. Zone, tether, airlocks, hazards and breaching implemented; zone damage and tether pull tested headless. |
| J. UI, lobby, results | Implemented. Smoke-tested headless (builds and updates without errors); layout unverified visually. |
| K. Progression, audio, effects | Implemented. DataStore progression tested headless with an in-memory store; audio uses placeholder built-in sounds. |
| L. Multiplayer testing & optimisation | **Outstanding.** Needs Studio multi-client sessions. |

## What is implemented

**Environment (procedural, `Builders/`).** About 3,200 parts plus terrain asteroids.
- *Meridian Station:* central hub. +Y Command Module with observation windows. -Y Docking Bay, an open
  hangar with a parked shuttle. -X Science Labs: a junction plus three labs, one damaged with sparks,
  smoke and a breachable hull. +Z Armoury → Observation Deck. -Z Hydroponics. +X spine → ring junction
  → Engineering with the reactor. An 8-segment Habitat Ring connects through two spokes. Also: 4 solar
  arrays, 5 exterior maintenance platforms, antennae and nav lights.
  - **Size:** the station is built at base scale and then enlarged 1.5× (`Station.Scale`), to about
    800 × 500 × 500 studs. Corridors and doors are now 18 studs wide. Furniture such as consoles,
    lockers, crates, benches and bunks keeps human size (`Kit.scaleBuild`).
  - **21 holo doors** (`Kit.holoDoor`) on exterior walls. These containment fields keep rooms
    pressurised, but players, bots and bullets pass straight through, giving fast entry with no airlock
    cycle. 5 airlocks remain as sealed routes.
  - **Lighting:**
    - glowing hull bands on every solid outer wall, and blue floor-edge strips in every room
    - a ceiling light ring in the hub
    - floodlights with SpotLights aimed at the hull
    - 12 blinking beacons, including at the station's extremities
    - a pulse of 48 "chaser" lights that sweeps around the habitat ring
    - shimmering holo-door fields. The client animates these, with no network cost.
- *ESV Long Horizon (exploration ship):* bridge, crew quarters, medical/research, a 120×50×70 cargo
  hold with catwalks, crane and container stacks, engineering with the reactor, engine room, and
  three engines. A dorsal spine on pylons forms a covered hull-traversal channel. Also a ventral keel,
  sponsons, a docking arm, and a hidden storage room that can only be reached by breaching a plate.
- *Asteroid field:* "The Anvil", a 90-stud rock with a bored tunnel and central chamber, plus 34
  clustered rocks, 2 mining platforms, 3 drill rigs, floating ore containers, and 45 scattered
  asteroids across the arena.
- *Derelicts and debris:* the Kestrel freighter wreck (three broken sections), a corvette wreck,
  satellites, escape pods (enterable, with loot), damaged cargo modules, broken solar panels,
  industrial debris, two cargo depots and a communications array.
- *Lobby:* a sealed hall outside the arena with a panoramic window, weapon display pedestals
  (equipment previews), a practice range with moving drones, a match status board and a controls board.
- *Backdrop:* a client-rendered cratered planet that stays at a fixed offset from the camera (always
  huge and distant, never reachable), a night sky with stars, bloom and colour grading.
- 15 airlocks, 21 holo doors, 53 pressurised volumes, 15 O2 stations, 93 loot spots, 30 deploy points, and
  7 final-zone candidates.

**Movement** (`MovementController`). The Humanoid is held in the Physics state with Workspace
gravity 0. An AlignOrientation turns the body toward the camera. Translation uses a momentum model:
camera-relative thrust on 6 axes, drift, a speed cap, boost energy, an exponential brake to a full
stop, tether pull, and server impulses for knockback, shoves and the boundary. The camera is
yaw/pitch with pitch clamped at ±85°, so the view can never flip or roll. The server checks speed
from actual displacement, rolls back teleports, and enforces the arena boundary.
**Air roll** (Q / E, rebindable): a barrel-roll dodge that throws you about 34 studs/s sideways. It
costs 22 boost energy and has a 0.9 s cooldown. The extra speed bleeds back to cruise like any other
overspeed.

**Character animation** (`CharacterAnimator`, every client, players and bots alike). Roblox's
walk/jump/fall animations are replaced by an empty `Animate` script, and every R15 joint is posed
procedurally each frame (`Motor6D.Transform`, in PreSimulation):
- **Flying:** the legs trail behind forward thrust, swing forward when reversing, tuck when
  descending, dangle when climbing, and sweep back streamlined while boosting. They flutter slowly
  when drifting.
- **Banking and rolling:** the body banks into strafes, and air rolls spin it a full 360°.
- **Weapons in the hands:** the gun is mounted on the HumanoidRootPart with a Motor6D, so it always
  points where its owner aims. Two-bone arm IK puts the right hand on the weapon's `Grip` and the left
  hand on its `Support` point in every pose.
  - The upper body turns into a bladed shooting stance, with the head turned back to look down the
    sights.
  - The gun sits at low ready, shoulders when aiming or firing, and kicks back on every shot.
  - Weapons are scaled to the body (`Config.Character.HeldWeaponScale`): a rifle is about 2.4 studs
    long, about half the body height.
- **Eliminated bodies** go limp and tumble. Characters stay in one piece (`BreakJointsOnDeath` off).
- **Replication:** other clients learn your aim from the `Aiming` character attribute, your rolls
  from `RollAt`/`RollDir`, and your shots from the tracer message, which names the shooter's
  character. Bots set the same attributes, shoulder their guns in fights, and air-roll to dodge when
  hit (skilled bots more often).
- **Cost and limits:** characters beyond 420 studs aren't updated, and beyond 160 studs they update at
  30 Hz. Arms and legs don't collide, so swinging limbs can't push the body.
- **Joints:** the place forces R15 avatars (`StarterPlayer.GameSettingsAvatar`) and opts out of
  Roblox's avatar joint upgrade. Any upgraded `AnimationConstraint` joints are converted back to
  `Motor6D`s when a body spawns (`CharacterService.UseMotorJoints`). The animator finds joints by
  the body part they move and can drive either kind.
- **Rounded pressure suit:** the blocky R15 body parts are hidden and covered with smooth ellipsoid
  shells, with armoured balls on the shoulders, elbows and knees, plus gloves and boots. The shells
  are welded to each limb, so they bend with it. The hidden parts still collide and take hits.
- **Output diagnostics:** about 6 s after joining, Output shows
  `[ZG] animator: posing N of M characters`. A character it can't animate gets a warning with its
  joint counts, and an R6 avatar gets a warning with the setting to change.
- `docs/animation/pose_sheet.png` is rendered from the real code by `tools/render_poses.py`.

**Bots** (`BotService`, `NavGraph`, `Config.Bots`). Every match and the lobby are kept at 20
combatants: with one player online there are 19 bots, and each player who joins replaces a bot from
the next match. Bots act only through the same validated server entry points as players: fire rate,
ammo, spread, aim cone, pickup range, cooldowns and airlocks. They move with the shared
`ZeroGMotion` model, so they get the same acceleration, caps, boost energy and braking.
- **Skill (0.72–0.93 per bot)** shapes reaction time (0.17–0.5 s), aim error that settles while
  tracking, headshot preference, strafe and jink rhythm, and grenade use.
- **Priorities:** storm, then oxygen, then fight, then heal or recharge, then loot, then hunt.
- **Navigation** uses a graph generated from the station, ship and wreck geometry: doors, airlocks
  (cycled like a player would) and exits through open space. It's backed by obstacle avoidance and
  an unstick routine.
- **Between matches** bots drift around the lobby and practise on the range drones.
- **Spectating:** eliminated players can watch bots.
- `Config.Bots.ShowTag` controls the "[BOT]" name tag.

**Match.** Waiting → Countdown → Preparing → Deploying → Active → Final → Ending → Results → Waiting.
- **Countdown:** every round is a 30-second lobby countdown, then **20 combatants** deploy. Queued
  real players come first and bots fill the remaining seats. If nobody is queued, it's 20 bots.
- **Last one standing wins.** When every real player is out, the storm collapses to nothing over
  25 s (`Config.Bots.CollapseWhenHumansOut`), so the bots-only remainder is decided quickly. The same
  sudden-death collapse runs if a match reaches its 15-minute limit.
- The storm hurts the weakest first and never eliminates the last combatant alive, so a match always
  ends with exactly one survivor.

Configurable min/max players. Deploy points are chosen spaced and validated as clear. Players get 4 s
of deploy protection. Eliminated players drop a suit locker and spectate (Q/E). Disconnects count as
eliminations. There's a time limit. Rewards are awarded and results shown, then the next round starts
automatically. Each player has a team id, so duos/squads only need team assignment.

**Combat.** 8 weapons: pistol, assault rifle, burst rifle, precision rifle, shotgun, SMG, the Helios
heavy energy cannon (splash), and the Arc Thrower (short-range defence). They differ in damage,
falloff, RPM, spread, ADS spread, recoil, magazine, reload, ammo type and mobility. Rarity gives
small damage and magazine bonuses. There's also melee with knockback and a thrown pulse charge.
The server validates fire rate (including burst), ammo, reload state, pellet count, origin distance,
aim cone and spread, then raycasts itself. Headshots deal ×1.5. Shields absorb damage first. Kill
attribution has a 12 s window. Clients get hit markers, directional damage indicators and a kill
feed. Other players see tracers.

**Loot and inventory.** Containers by tier (crate/locker/pod/cache). Five rarities with tier-weighted
odds. Ammo, consumables (stim, trauma kit, O2 canister, shield cell), armour tiers, utilities
(pulse charge, tether spool) and upgrades (boost cell, O2 recycler, thruster tune). 3 weapon slots,
backpack stack limits, ammo caps, a weapon swap that drops the old weapon, an inventory screen with
tooltips, use/drop, and server-validated pickup range.

**Oxygen.** Drains in vacuum and refills in pressurised volumes. O2 stations have a cooldown. After a
grace period at 0 O2, hypoxia damage starts. Breaching a hull plate depressurises that compartment.
The O2 recycler upgrade reduces use. Players get HUD status, a low-O2 vignette and warning beeps.

**Storm.** A shrinking sphere over 6 stages. Each stage moves toward one of 7 final-zone candidates,
and each new sphere always fits inside the previous one. Players get announcements and a 15 s warning.
Damage escalates each stage. On the client: a sphere visual, a tint while inside the storm, and a
tactical map that shows the current and next ring plus whether the safe centre is above or below you.

**Hazards.** Electrical faults warn → discharge on a cycle. Reactor radiation volumes. Explosive cargo
barrels with a fuse, which chain. Smoke in damaged rooms. Flickering lights. Interlocked airlocks:
only one door opens at a time, with a pressure cycle in between.

**UI.** An "orbital HUD" style throughout (`UIKit`):
- **Look:** deep-space glass panels with light-catching cyan edges and HUD corner brackets.
- **Type:** Michroma display type, Titillium body text and Sarpanch readouts.
- **Controls:** segmented telemetry bars, and buttons with an accent rail and animated hover glow.
- **Main menu:** full screen. A twinkling starfield fades out to the right so the lobby window
  (station and planet) shows through. Gradient logo, glyph navigation, a pilot card with an XP bar,
  an orbit status chip (phase, pilots and bots), a big DEPLOY call to action, and slide-in
  animations.

Main menu pages: Deploy/queue, Practice, Loadout (4 side-grade kits), Locker (6 suit finishes by
level, titles), Settings (sensitivity, FOV, invert Y, key rebinding, control reference),
Statistics, Tutorial (8 pages) and Credits. HUD: health, shield, O2, boost, suit status,
tether/pulse counts, weapon, ammo, slots, phase/timer/survivors, kill feed, tactical map, crosshair,
hit markers, damage arrows, notices, use/reload progress and a spectate banner. Results screen:
placement, kills, damage, survival time, XP, credits and level up. Everything scales with screen size.

**Progression.** DataStore saves with UpdateAsync, retries, autosave, BindToClose and a
no-regression guard. It never overwrites data after a failed load. It falls back to temporary data
in Studio, with a warning shown. Cosmetics only: no paid items and no random rewards.

## Tests performed

**Automated: `python3 tests/run.py` → 62 passed, 0 failed** (about 3 minutes, most of it the simulated bot match).
Every run checks member access against Roblox's real API tables, so an invalid property name or a
write to a read-only property fails the test that reaches it.
- *Pure logic:* the CFrame mock; all 8 weapons complete; damage falloff is monotonic; time-to-kill is
  ≥ 0.4 s against 200 effective HP; 9,000 loot rolls are valid (ammo comes with weapons, no
  legendaries in the low tier, heavy weapons are never common or uncommon); loot quality rises with
  tier; 2,000 random zone steps always stay nested; the zone schedule is monotonic, converges, fits
  the match time and escalates damage; the XP curve and unlocks behave.
- *Environment:* the world builds without errors. Part budget and marker counts are checked. Every
  corridor, the spine and ring tubes, and every airlock are passable for a character (centre line
  plus a 2.6-stud ring of samples). No deploy point, loot spot, O2 station or final zone is inside
  geometry or terrain. Deploy points are spread out and inside the zone. The lobby is sealed (400
  rays). Pressurisation covers interiors but not the hangar or open space.
- *Server simulation:* two players join, load profiles and spawn in the lobby. Practice shots are
  validated and harmless. The countdown runs, then both players deploy apart with full kits. Deploy
  protection holds. The server rejects a far origin, a wrong pellet count, aim behind the body, and
  fire-rate abuse, and ignores malformed packets. Lag compensation registers a shot at where the
  shooter saw a strafing target, refuses rewinds beyond the cap, and is blocked by walls. Shields
  absorb damage. Reload timing and reserve are
  correct. Inventory stacks, caps, weapon swaps and upgrades work. Containers refuse a far searcher,
  then spawn pickups that go into the inventory. Oxygen drains, the grace period holds, hypoxia
  applies, and O2 refills inside. The storm damages players outside. On elimination: the kill is
  credited, the kill feed fires, a death locker spawns, the winner is declared, and results and XP
  are saved. The match returns to the lobby, a second match starts automatically, and a mid-match
  disconnect ends it cleanly. No server thread errors occur.
- *Character animation* (the mock now builds full R15 rigs with Motor6D joints, and a joint solver
  places every part from C0 · Transform · C1⁻¹):
  - Guns are mounted at the aim grip and scaled to the body. The server copy points along the aim.
  - Both hands sit within 0.05 / 0.12 studs of the Grip / Support points while idle, aiming, firing,
    flying forward, reversing, climbing, descending, strafing, boosting and mid-roll. The last run
    measured 0.000 for both.
  - The aimed barrel is within 3° of the view direction. Ready tips it 20–40° down. A shot kicks it
    back.
  - Poses respond to motion: legs trail forward flight and tuck when descending, the body banks into
    strafes, and boosting streamlines the legs.
  - Q/E rolls throw the pilot sideways, cost boost, respect the cooldown and replicate. The body turns
    upside down mid-roll and settles upright afterwards.
  - Aim, shots and rolls reach other clients, and bots are animated the same way.
  - Dead bodies tumble with limbs spread, and no transform is ever non-finite.
  - The mock can build Roblox's upgraded rigs, with `AnimationConstraint` joints between rig
    attachments. They are converted to 15 `Motor6D`s on spawn, matching the attachments, and the
    animator also poses an unconverted upgraded rig with the hands on the gun.
  - The suit hides all 14 blocky parts and adds at least 14 smooth shells and 6 joint balls, none of
    which block shots. The knee pad stays on the knee while the knee bends.
- *Client:* the real MovementController is driven frame by frame. Thrust caps at cruise speed, drift
  persists, X stops fully, all six directions are camera-relative, diagonal thrust isn't faster,
  boost is capped and runs out of energy then bleeds back to cruise, the tether pulls and releases,
  and impulses apply. ClientMain boots every controller. Every server-to-client message type is
  handled, and the HUD runs through every phase, spectate and results without errors.
- *Bots:*
  - The nav graph reaches all 50+ pressurised interiors from open space, and the hub-to-ship route
    cycles an airlock.
  - With one player online, 19 bots fill the lobby and are published for spectating. They drift
    around and practise on the range without hurting anyone.
  - A full 20-combatant match plays out to a bot winner, using a 0.35× storm schedule so the test
    stays fast. In the last run: 186 s, 15 of 19 eliminations were bot kills, and bots split their
    time between looting, fighting, refilling oxygen and outrunning the storm.
  - Bots never trip the anti-cheat or the fire validation.
  - Afterwards the bots return to the lobby, and a joining player replaces a bot.
  - In the next match (20 combatants), once the real players are eliminated the storm collapses and
    the match ends with exactly one combatant alive, who is declared the winner.
  - With nobody queued, the 30-second countdown still runs and 20 bots deploy. The match ends when
    one is left.
  - The headless physics moves bodies by their velocity but doesn't collide them, so this proves the
    decisions and validation, not wall-hugging.
- *Bot tuning found by these tests:*
  - Bots duelled with starter pistols across open space. They now engage only within effective range.
  - Oxygen lost out to the storm and to fights. Critical O2 now comes first, with planned refills
    below 38%.
  - Boost acceleration out-ran the speed cap. The motion model is now shared by bots and players.

**Static analysis:** `luau-compile` gives a clean syntax pass on every file. `luau-lsp analyze`
(Roblox definitions, non-strict) reports 0 errors. The only remaining note is a deprecation hint on
the `LoadCharacter` fallback.

**Studio playtest report: "can't kill anybody and stuck in practice".** Diagnosis and fixes:
- *Shots at moving targets missed.* The server raycast against where bots are *now*, but your screen
  shows them about one round trip plus Roblox's interpolation delay in the past. A strafing bot was
  several studs from where you aimed, so on-target shots missed and only the static range drones
  could be hit. The new `LagCompensation` service keeps one second of position history per combatant
  and re-tests shots that miss every current body against the target where the shooter saw it. A
  test checks that a shot at the seen position hits, a shot older than the cap misses, and walls
  still block.
- *After dying you waited in the lobby while 19 bots finished the match*, which could take up to
  15 minutes. Once every real player is out, the storm now collapses (see **Match**), so the last bot
  standing wins within about 30 seconds and the next countdown follows.
- *The big menu button read "LEAVE QUEUE" for queued players*, so pressing it took you out of
  matches. Pressing "PRACTICE RANGE" did the same. **DEPLOY** is now always the big button and always
  means "put me in the next match". Leaving the queue is a separate, smaller button. The lobby HUD
  says "NOT QUEUED - press M, then DEPLOY" when you aren't queued.
- *Test blind spots closed:*
  - The mock now loads Roblox's real API member tables (`tests/api/roblox_api.luau`, generated by
    `tools/gen_roblox_api.py`). Reading or writing a member that doesn't exist, writing a read-only
    property, or assigning the wrong value type now throws, as it does in Roblox. Every UI, builder
    and server path in the suite passes under it.
  - The client boot test now fails when a controller only logs a startup failure.

**Studio playtest report 2: "characters are still blocky, no knees or elbows, guns are not in
hands, characters have no animation at all".**
- *Probable cause: Roblox's avatar joint upgrade.* New characters can use `AnimationConstraint`
  joints instead of `Motor6D`s, and the animator only looked for `Motor6D`s. On upgraded bodies it
  found no joints, so nothing was posed. Limbs stayed straight with no visible knee or elbow bends,
  the hands never reached the gun, and the gun floated in front of the chest.
- The headless rig only had `Motor6D`s, so the tests couldn't see this.
- *Fixes:* opt-out in the place, conversion on spawn, an animator that handles both joint kinds, and
  Output diagnostics (see **Character animation**). Upgraded rigs are now part of the tests.
- *Blocky look:* the rounded pressure suit replaces the blocky body. Knees, elbows and shoulders are
  armoured joint balls, so bends are obvious.
- *Still unverified in Studio.* If the Output line doesn't say "posing N of N", or the animator
  prints a warning, that text pinpoints the remaining problem.

**Defects found and fixed by these tests:**
- Corridor "ribs" were solid slabs that sealed every straight corridor. They are now open frames.
- Boost acceleration out-ran the soft-cap bleed, so boosting exceeded the speed cap indefinitely.
- Kill credit depended on event timing. The attacker was recorded after the health change that fires `Died`.
- The final phase triggered instantly in matches with 3 or fewer players.
- Several loot spots and an O2 station were embedded in columns, bunks, pylons and asteroids. Asteroid
  props now sit on the real rock surface.
- A deploy point was inside an asteroid.
- The captain's chair blocked the command-module hatch.
- If deploy points ran out, everyone would stack on one spawn.
- An ambiguous Luau statement in the storm visual.

## Known defects / limitations

- **Bots are untested in real Roblox physics.** In the headless simulation bodies don't collide, so
  avoidance, unsticking and airlock cycling against real collisions need a Studio check. Watch for
  bots snagging on furniture or hovering at closed doors.
- **Bot tracer traffic.** Every bot shot sends a tracer to every client. Batching (roadmap #47) is
  advisable before running many servers.

- **Lag compensation is tuned by estimate.** Shots that miss a target's current body are re-tested
  against where the shooter saw it: ping plus an assumed 0.12 s of Roblox interpolation, ±0.1 s,
  capped at 0.5 s. If hits still feel off in a real server, tune `Config.LagCompensation`.
- **Animation is procedural and unverified in Studio.** It has been checked numerically and in
  rendered pose sheets on a blocky R15 rig with approximate joint offsets. Real avatars, especially
  Rthro proportions, may need tuning:
  - `Config.Character.AimGrip` sets where the gun sits.
  - `READY`, `BLADE` and the `POLE` elbow hints are at the top of `CharacterAnimator`.
  - If an avatar's arms are too short to reach the support point, the left hand stops just short of it.
- **No animation assets.** Poses are code-driven, so there are no keyframed flourishes such as
  reload or weapon-switch animations.
- **Air roll has no gamepad binding yet.**
- **Placeholder audio.** It uses Roblox built-in client sounds such as `paintball.wav` and
  `electronicpingshort.wav`. There's no breathing loop, only low-O2 beeps. Swap in licensed assets
  in `EffectsController.SOUNDS`.
- **Visual art is a procedural first pass.** It's box and cylinder geometry, not meshes. The
  octagonal tubes stand in for round habitat modules.
- **Unverified rendering tricks:**
  - The storm sphere uses ForceField material plus a negative-scale SpecialMesh copy so it can be
    seen from inside.
  - The space sky relies on `ClockTime = 0.2` (stars, low "moon" light) rather than a custom skybox.
  - Both need checking in Studio. If the sky looks wrong, add a Sky with dark skybox textures.
- **Other players don't see your boost plume.** It's local-only.
- **Key rebinding isn't saved** between sessions. Sensitivity, FOV and invert Y are saved.
- **No touch controls.** Input is abstracted in `InputController`, but mobile thumbsticks and buttons
  aren't built yet. Gamepad is mapped.
- **Squads and duos aren't exposed.** The data model and damage rules already support teams.
- **Titles are listed but can't be equipped.**
- **StreamingEnabled is off.** The map is about 2,800 parts, which is fine without it. Turning it on
  needs ReplicationFocus/streaming checks for client lookups such as FinalZone markers on the map.

## Required manual actions

1. Open `build/ZeroGravity.rbxlx` in Studio and press Play. Check the Output for `[ZG] world complete`.
2. **Playtest movement first:** Test → Clients and Servers, 2 players. Tune `Config.Movement`
   (accel, caps, brake) and `TurnResponsiveness` for feel.
3. Visual pass: check the lighting, sky, planet backdrop, storm sphere (from inside and outside),
   tracer readability and UI scale. Adjust `Builders/Backdrop.luau` and `EffectsController`.
4. Replace the placeholder sounds with licensed assets.
5. Before publishing, enable *Studio Access to API Services* so DataStores work in Studio.
6. Run a multi-client stress test (8–24 players). Watch network receive rates and the server
   heartbeat under combat.

## Remaining dependencies

None at runtime. There are no external assets, packages or free models. Optional tools:
- Rojo, for live sync.
- The `luau` CLI and matplotlib, for tests and renders.
- luau-lsp, for type checking.

## Files

Everything under `ZeroGravity/` is new:
- `src/`: 10 shared modules, 7 builders, 15 services, 2 bootstraps, 9 client controllers and the empty `Health` override.
- `tests/`: `mock.luau`, `specs.luau` and `run.py`.
- `tools/`: `build_place.py` and `render_blockout.py`.
- `docs/blockout/*.png`
- `build/ZeroGravity.rbxlx`
- `README.md`, this file, and `default.project.json`.

Nothing outside `ZeroGravity/` was modified.
