# Harbourlife Build Progress

A system is only marked complete when it works in Play Mode.

| Phase | System | Status |
|---|---|---|
| 0 | Project audit | Done: repo was empty; fresh Rojo project chosen |
| 1 | Core framework | In progress. Written, NOT yet tested in Play Mode. Written: data/save, money/bank, inventory, notifications, HUD, progression + skills, jobs, interaction service, placeholder Job Centre. Inventory/skills panel (press I) added. Missing: Studio Play Mode testing |
| 2 | Pizza Business | Core loop VERIFIED in Studio by developer (cook, serve). Remaining items below not built. Written/other parts NOT tested in Play Mode. Supplier, ovens, counter + delivery orders, payment, XP, reputation. Missing: employees, business ownership, packaging, fuel/vehicle link, customer NPCs, till UI |
| 3 | Vehicles | Written, NOT tested. Ownership, spawn/store, shop, fuel, wear, repair, owner-only seat, placeholder sedan/pickup/van/excavator. Missing: purchase UI, insurance, customisation, collision damage |
| 3b | Excavator | VERIFIED by developer: driving, arm, detailed model, digging and dumping. Swing/boom/stick/bucket servos, terrain dig + dump, load limit, construction skill. Needs tuning (arm geometry, stability, reach) |
| 4 | Retail | Written, NOT tested. Shared ShopService + shop UI: grocery, general store, clothing, electronics, hardware, fishing shop, furniture, pet store, gun shop (clothing/display only). Server-validated price, range, qty, stock with restock. Missing: shop staff job + till, NPC shoppers, wearing clothing (needs clothing assets), using items |
| 4b | Harbour Mall | Written, checked in an offline simulation of the builder (no Studio here), NOT tested in Play Mode. Generated to fit the `MallSite` and `CarParkSite` Parts: two levels, atrium with glass skylight, 4 escalators, 3 lifts, 16 themed stores (7 new: pharmacy, sports, shoes, jewellers, books, toys, music), each with shop floor, till, stockroom, staff room and loading door. Multi-storey car park with ramps and a footbridge. Automatic sliding doors (21), moving escalator steps, stairs, directories, ATMs, toilets, food court (4 kiosks), Mall Cleaner and Mall Security jobs, NPC shoppers that buy real stock. See docs/MallSetup.md. Missing: shop staff job, goods lifts, NPC shoppers using the escalators |
| 5 | Food | Written, NOT tested. Shared FoodService for café, bakery, restaurant, fast food: Food Wholesaler supplier (shop), stations per business (coffee machine, toaster, bakery oven, stove, grill, fryer), 12 menu recipes, customer orders with on-counter order board, expiry, payment, job pay (barista, baker, chef, waiter, fast food worker), XP, reputation. Missing: customer NPCs, table service, packaging, delivery (Phase 6), employees/ownership (Phase 18) |
| 6-22 | Remaining phases | Not started |

Phase 1 started on developer approval (fresh Rojo project). Nothing is marked complete until verified in Studio.
