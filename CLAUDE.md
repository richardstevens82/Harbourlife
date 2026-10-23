# Harbourlife

Roblox town life game written in plain Luau, laid out like a Rojo project (`default.project.json`):
- `src/ReplicatedStorage/Shared`: definitions (items, shops, jobs, recipes, businesses, the mall)
- `src/ServerScriptService/Systems`: server systems, started in order by `Main.server.luau`
- `src/StarterPlayer/StarterPlayerScripts`: client UI and visuals

`python3 tools/build_place.py` writes `build/Harbourlife.rbxlx` from `src/`. Rebuild it after every change.

**Installing into the developer's Studio place (mall, food court, jobs, NPC shoppers): follow
`docs/ClaudeInstallGuide.md` step by step.**

Master spec: `docs/spec/things_to_add_to_Harbourlife.txt`. Trackers: `docs/HarbourlifeBuildProgress.md`,
`docs/HarbourlifeKnownIssues.md`, `docs/HarbourlifeAssetRequirements.md`.
Rules: the server owns all money, stock and rewards; one system at a time; nothing is complete until it works in Play Mode.
