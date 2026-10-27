# Handoff: continuing ZERO GRAVITY: LAST ORBIT on your PC

This project was built in a Claude Code cloud session. This note is for whoever picks the work up
locally, whether that's you or Claude Code on your desktop. It covers where things are, how to run
the checks, and what was asked for next.

## Where everything is

- **Repository:** `richardstevens82/Harbourlife`, in the `ZeroGravity/` folder only. Nothing outside
  that folder belongs to this game.
- **Branch:** `claude/practical-newton-u6vpeq`. Draft PR:
  https://github.com/richardstevens82/Harbourlife/pull/2
- **Latest shipped update:** artificial gravity inside the station, ship and wrecks (commit 8025629).
- **Playable place file:** `build/ZeroGravity.rbxlx`, rebuilt by `python3 tools/build_place.py`.
- **What works and what's unverified:** `BUILD_STATUS.md`. Controls and layout are in `README.md`,
  and ideas are in `docs/ROADMAP_50.md`.

## Important: Studio edits are not in the project

The world, UI and characters are all generated from the code in `src/`. Opening a freshly built
`ZeroGravity.rbxlx` in Studio gives you only what is in this repository. Anything added by hand in
Studio is not included, such as the **Voyager character model** in the place called "Zero Gravity
PvP Beta". To keep such changes, bring them into the project:
- **Recommended:** turn on Roblox Studio's built-in MCP server and connect Claude Code to it, so
  Claude can read the open place directly.
- **Alternatively:** save the place with **File → Save to File As… → .rbxlx**, or right-click the
  model, choose **Save to File** and save it as `.rbxmx`, then put the file in `ZeroGravity/beta/`.

## Running the checks locally

You need Python 3 for these:
- **luau:** for tests and pose renders. Get it from https://github.com/luau-lang/luau/releases and
  put `luau` on PATH, or pass its path to `run.py`.
- **luau-lsp:** optional, for type checking. Get it from
  https://github.com/JohnnyMorganz/luau-lsp/releases, plus `globalTypes.d.luau` from that repository.
- **matplotlib:** for `render_poses.py` and `render_blockout.py`.

```
python3 tools/build_place.py        # build/ZeroGravity.rbxlx + sourcemap.json
python3 tests/run.py                # 75 tests, about 3.5 min; expect "75 passed, 0 failed"
python3 tools/render_poses.py       # docs/animation/pose_sheet.png
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions=@roblox=globalTypes.d.luau --no-strict-dm-types src
# Expected: no errors, just one DeprecatedApi hint on LoadCharacter.
```

## The routine after every change

1. Rebuild the place.
2. Run the tests and the type check. Add tests to `tests/specs.luau` for new behaviour. The mock in
   `tests/mock.luau` checks every Roblox member name against the real API.
3. Update `BUILD_STATUS.md`, `README.md` and the roadmap.
4. Commit and push to the branch above, then update the PR description.

## Next request (not started yet)

The user asked for the following, in their words: "add 3rd and 1st person view switch with aim down
sights - make sure characters look awesome and are the new voyager model i added - make sure that
when battling in space outside you can see things properly - use blender to create the most
realistic models you can". Notes for each part:

1. **First/third-person switch with aim-down-sights.**
   - The camera is in `Controllers/CameraController.luau` and aiming in `CombatController`.
   - The `Aiming` attribute already replicates.
   - Guns are mounted with a Motor6D `WeaponMount` on the HumanoidRootPart, with hand IK in
     `CharacterAnimator`. Weapon models are in `Shared/WeaponModels.luau`, so a sight point can be
     added there.
2. **Voyager character model.**
   - It is in the user's Studio place, not in this repository. Bring it in first, as described above.
   - `CharacterAnimator` needs an R15 rig: Motor6D or AnimationConstraint joints with standard part
     names.
   - `CharacterService.suitBody` currently hides the blocky parts and welds rounded shells on.
     Replace that with the Voyager meshes, welded to each limb or used as the StarterCharacter.
   - Bots get the same body.
3. **Seeing clearly in open space.**
   - Lighting and exposure are in `Builders/Backdrop.luau`, and effects in `EffectsController`.
   - Ideas: rim or suit lights on characters, a subtle enemy outline or Highlight at range, and
     brighter tracers.
4. **Blender models.**
   - The cloud session got Blender running headless (`pip install bpy` on Python 3.13). Locally you
     can use the Blender app, or connect Claude to it with Blender MCP:
     `claude mcp add blender -- uvx blender-mcp`.
   - Export FBX and import it with Studio's 3D Importer. Roblox only uses meshes uploaded to your
     account, so meshes can't be embedded in the generated `.rbxlx` by the build script.
