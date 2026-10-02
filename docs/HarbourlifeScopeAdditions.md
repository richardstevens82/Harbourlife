# Harbourlife Scope Additions

Additions made after the master prompt. All follow the master rules: server authority, no pay-to-win, one system at a time, no survival mechanics.

## Prison Island
- Restricted island reached by secure ferry only.
- Facility: cell blocks, intake, visitor centre, medical, kitchen, laundry, workshop, exercise yard, control room, gates, watchtowers, secure harbour, staff housing, garage.
- Player jobs: Prison Officer, Transport Officer, Medic, Cook, Cleaner, Maintenance, Administrator, Security, Workshop Supervisor, Transport Driver, Prison Ferry Operator.
- NPC prisoners on a daily routine: wake, breakfast, work/education, exercise, lunch, work/recreation, dinner, cell.
- Chain: Police arrest, station, court/processing, prison transport, ferry, prison island.
- Players do not commit crimes to be imprisoned; the justice system is NPC-driven.
- Events: medical emergency, fire, lockdown, transport breakdown, riot response, supply delivery, search operation.

## Further locations and systems
| Item | Notes |
|---|---|
| Pet store | Pets and pet clothes; pet cosmetics are an allowed Robux category |
| Gun shop with clothes | Needs developer decision (see audit). Default: cosmetic/display/clothing only |
| Sewer system | Road drains, ladders in and out, maintenance jobs; streamed zone |
| CCTV system | Detects NPC crime events and feeds police dispatch |
| Car showroom | Display cars, purchase flow into the vehicle ownership system |
| Airport | Planes, jumbo jets, helicopters; airport transfer driver job; ticketing reuses the universal ticket system |
| Mobile phone | In-game apps: taxi, police, maps, bank, jobs; server-validated requests |
| Giant squid | Rare random boat-attack event; damage and rescue jobs; no survival loop |
| Build your own house | Build, use, and sell for profit; extends Phase 10 property system; server-validated saves |

## NPC Life (expanded Phase 19)

NPCs have: Home, Job, Schedule, Destinations, Spending habits, Favourite locations, Transport preferences, Social behaviour.

Example day: HOME, WORK, CAFE, SHOP, PARK, HOME.

NPC activities: shop, eat, work, walk, visit parks, cafes and restaurants, use taxis and buses, go fishing, visit harbour and beach, attend events.

### Implementation notes
- Use Roblox `PathfindingService` for appropriate navigation.
- Data-driven `NPCDefinitions`: each NPC has `home`, `job`, `schedule[]` (time block to destination type), `spending` (budget per day, preferred shop categories), `favourites[]`, `transport` (walk/bus/taxi/car/ferry weights), `social` (friends, group tendency).
- Central `NPCSystem` scheduler, not one script per NPC.
- Simulation levels: near the player gets full path-following and animation; mid distance gets simplified movement; far gets abstract state only (position inferred from schedule).
- Path request budget per frame and a cached waypoint graph for common routes (home to bus stop, etc.).
- NPC spending must go through `EconomySystem` so it creates real customer demand (the existing Pizza Business gold standard).
- Fall back to straight-line or teleport-on-schedule at far distance if a path fails; log failures to Known Issues.
