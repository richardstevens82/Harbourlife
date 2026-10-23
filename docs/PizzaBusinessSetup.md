# Pizza Business: Studio setup

Name Parts in Workspace (anchored, any size) and the server wires them up:

| Part name | Role |
|---|---|
| `JobCentre_pizza_cook` / `JobCentre_delivery_driver` | Take the job |
| `PizzaSupplier` | Buys one set of ingredients ($9) |
| `PizzaOven_1`, `PizzaOven_2` | Cook: needs dough + sauce + cheese; 10s minus cooking level (min 4s) |
| `PizzaCounter` | Serves counter orders |
| `PizzaDropoff_1`, `_2`, ... | Delivery destinations |

Test loop: take job, buy ingredients, use oven, wait, use oven again, serve at counter (or deliver). Orders only spawn while a player holds the cook or driver job. Press I for inventory and skills.

A dev-only `TestWorld` module builds all of these Parts automatically on server start (set `Enabled = false` in `TestWorld.luau` once your real map has them).

## Vehicles (Phase 3)

TestWorld also builds: `VehicleSpawn`, `VehicleGarage_<sedan|pickup|delivery_van|excavator>`, `VehicleShop_<pickup|delivery_van|excavator>`, `FuelStation`, `Garage_Repair`.
Everyone starts owning a free sedan. Use the sedan garage pad to take it out, sit in the seat (on top of the body), drive with WASD. Buy the excavator ($8000) at its shop pad; drive it near the pump to refuel.

## Excavator (testing)

TestWorld gives every player an excavator for free and builds a dirt mound (east of the floor, sign: `DigZoneSign`).
Take it out at `VehicleGarage_excavator`, drive with WASD. Hold Q/E swing, R/F boom, T/G stick, Y/H bucket; hold X to dig and Z to dump (bucket teeth must be in the dirt; holds 5 loads, dirt shows in the bucket). Or use the Drive prompt on the seat inside the cab.

## Shops (Phase 4)

All retail shops now live in Harbour Mall (see `docs/MallSetup.md`); each store's till counter is the Part `Shop_<id>`.
Use Browse, click Buy. Stock goes down per server and restocks over time. Walking away closes the window. Any Part
named `Shop_<id>` in your own map still works the same way.

## Food businesses (Phase 5)

Same idea as the pizza shop, for four businesses. Part names:

| Business | Counter | Stations |
|---|---|---|
| Café | `CafeCounter` | `CafeCoffeeMachine_<n>` (coffee, tea), `CafeToaster_<n>` (cheese toastie) |
| Bakery | `BakeryCounter` | `BakeryOven_<n>` (bread, croissant, cupcake) |
| Restaurant | `RestaurantCounter` | `RestaurantStove_<n>` (roast chicken, curry, soup) |
| Fast food | `FastFoodCounter` | `FastFoodGrill_<n>` (burger), `FastFoodFryer_<n>` (fries, nuggets) |

Ingredients come from `Shop_food_wholesale`. Jobs: `JobCentre_barista`, `_baker`, `_chef` (level 3), `_waiter`, `_fast_food_worker`.
Test loop: take a job, buy ingredients, use a station (it picks the recipe for the oldest open order you can make), use it again to collect, then serve at the counter. The board above the counter lists open orders. Orders only appear while someone holds one of that business's jobs.
TestWorld builds all of these in four rows east of the pizza shop.
