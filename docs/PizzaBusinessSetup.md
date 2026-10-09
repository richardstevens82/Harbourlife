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
