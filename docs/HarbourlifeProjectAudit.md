# Harbourlife Project Audit (Phase 0)

Date: 2026-10-02
Source of truth: `docs/spec/things_to_add_to_Harbourlife.txt` (master instructions + addenda)

## Result: the repository is empty

The repo (`richardstevens82/Harbourlife`) contained no commits and no files when audited.
There is no Roblox Studio project, place file, script or asset export in it.

| Audit item | Finding |
|---|---|
| Existing town layout | None in repo |
| Roads / buildings / terrain / water | None in repo |
| Harbour / islands / bridges | None in repo |
| Vehicles / boats | None in repo |
| NPCs | None in repo |
| Scripts / systems / UI | None in repo |
| Assets | None in repo |
| Transport routes | None in repo |
| Potential ferry locations | Cannot be assessed |
| Potential tunnel location | Cannot be assessed |

## What I need from the developer before Phase 1

The audit can only be completed against the real Studio project. Please provide one of:

1. A Rojo-style source export (`src/`, `default.project.json`) or `.rbxl`/`.rbxlx` committed to the repo; or
2. Confirmation that the project is new and should be scaffolded from scratch (recommended layout below).

## Proposed scaffold if starting fresh (Rojo + Wally-free, plain Luau)

```
default.project.json
src/
  ReplicatedStorage/Shared/{Config, *Definitions}
  ReplicatedStorage/Modules/   (shared modules)
  ServerScriptService/Systems/ (server-authoritative services)
  StarterPlayerScripts/        (UI, interaction, client views)
docs/
```

Architecture follows spec section 38. Server owns money, inventory, jobs, rewards, tickets, vehicles, ferries (spec section 39).

## Scope additions captured since the original master prompt

See `docs/HarbourlifeScopeAdditions.md`:
Prison Island, pet store, gun shop, sewers, CCTV, car showroom, airport, mobile phone, giant squid, player-built houses, and the expanded NPC Life specification.

## Potential conflicts to resolve with the developer

- **Gun shop**: RESOLVED by developer. Cosmetic, clothing and display items only; no functional weapons.
- **Giant squid vs "no survival"**: acceptable as a rare environmental event against boats (damage and rescue jobs), with no player-death survival loop.
- **Sewers vs performance**: needs streaming and a separate low-detail traffic-free zone.
- **Airport** is a large new location; schedule it after Phase 15 or treat it as a new island.
- **CCTV detecting criminals**: must stay NPC-driven (NPC crime events), consistent with the prison design.

## Performance concerns (design-time)

- Many NPCs with PathfindingService: use simulation levels, a pathfinding request budget and a shared path cache.
- Tunnel, sewers and airport need streaming and distance-based activation.
- Ferries carrying player vehicles need server-side physics ownership handling.

## Recommended development order

Unchanged from spec section 41 (Phases 1-22), with the additions slotted in:

- Phase 7: CCTV, prison staff roles, police-to-prison chain
- Phase 12: Prison Island, Airport (as a location)
- Phase 14: Sewers alongside the tunnel work
- Phase 19: NPC Life (full spec in the additions file)
- Phase 22: Mobile phone apps polish; giant squid event (Phase 20)

## Status

Phase 0 is **blocked on project source**. No building has been started. Waiting for developer approval before Phase 1.
