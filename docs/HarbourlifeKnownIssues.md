# Harbourlife Known Issues

| # | Issue | Status |
|---|---|---|
| 1 | Repository was empty; fresh Rojo scaffold created | Resolved |
| 2 | Gun shop: decided cosmetic/clothing/display only, no functional weapons | Resolved |
| 3 | Phase 1 code untested in Roblox Studio (no Studio in this environment) | Open |
| 4 | DataService uses plain DataStore SetAsync with no session lock; consider ProfileStore before launch | Open |
| 5 | Vehicle driving physics (LinearVelocity plane mode, client driven) need tuning in Studio; expect first-run handling issues | Open |
| 6 | Excavator dig did nothing: ReadVoxels result iterated with generic for (hits Size field) | Fixed, awaiting retest |
| 7 | Mall is about 9,000 parts at default size. Enable Workspace.StreamingEnabled before launch; consider lowering product density on mobile | Open |
| 8 | Lift car and escalator conveyors use physics (prismatic servo, anchored-part velocity); need Play Mode checks with several riders | Open |
| 9 | Skylight gable wedges may face the wrong way (WedgePart orientation unverified without Studio) | Open |
| 10 | Upper-floor stores have no goods lift yet (a GoodsLift_<id> marker only) | Open |
