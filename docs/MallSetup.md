# Harbour Mall: setup

The mall holds all retail. It is generated to fit your map, so you only mark out where it goes.

## 1. Mark the sites (Studio, edit mode)

1. Delete the roads, trees and buildings inside the area you outlined for the mall and the car park.
2. Insert a Part named **`MallSite`**. Anchor it, make it 1 stud thick, lay it flat on the ground and scale it
   over the whole mall area (the 2x2 blocks in your sketch, including the road that used to cross the middle).
3. Insert a Part named **`CarParkSite`** the same way over the car park area (the 1x2 blocks next to the mall).
   Leave the road between the two sites: the footbridge crosses it.

The builder turns the mall so its car park entrance and footbridge face `CarParkSite`. The building is set back
26 studs from the `MallSite` edges for the entrance canopies, planters and plaza. Both site Parts are hidden once built.

## 2. Build it

- **At runtime (default):** press Play. `MallService` builds the mall in about a second when the place has a
  `MallSite` but no `HarbourMall` model.
- **Baked into the place (so you can hand-edit it):** in edit mode, run in the command bar
  `require(game.ServerScriptService.Systems.MallBuilder).Build(true)`. A `HarbourMall` model appears in Workspace;
  save the place. From then on it is never rebuilt automatically. Run the same line again to rebuild from scratch
  (this replaces any hand edits).

## What gets built

| Part of the mall | Details |
|---|---|
| Building | Two levels (24 studs each). Stone cladding, blue LED band, bronze-framed glass entrance towers on all four sides with canopies, planters and lamp posts. Roller-door loading bays on the back walls |
| Concourse | Cross-shaped. Cream marble floor with dark inlay bands. Benches, planters and lighting |
| Atrium | Two open voids under a pitched glass skylight with a steel grid, with glass balustrades. A central bridge links the north and south galleries |
| Escalators | 4 (an up and a down pair in each void), meeting at the central bridge. The steps are conveyors that carry players, with moving step edges drawn on each player's screen |
| Automatic doors | Glass sliding doors on all 4 entrances, the footbridge entrance and every store. They open when a player comes within 11 studs and close behind them |
| Stairs | A marble staircase in each of the north and south arms, with glass balustrades |
| Directories | Store directory boards inside every entrance and at the top of each staircase, listing the stores by floor |
| ATMs | One in each arm: deposit or withdraw $100 to and from the bank (E / F) |
| Toilets | At the end of each upper arm, with cubicles, basins and mirrors |
| Lifts | 2 glass lifts in the north and south arms. Click CALL outside, or a floor button inside. The doors only open when the car is at that floor |
| Stores | 16 units (8 per level), each about 100 x 190 studs. Each has: its own colours, floor material, sign font, layout and feature pieces; a glass shopfront and LED fascia sign; a till counter (`Shop_<id>`, the Browse prompt); stocked fixtures; a STAFF ONLY door to a stockroom with pallet racking; a staff room (table, lockers, kitchenette); and a loading door (`LoadingDoor_<id>`, or `GoodsLift_<id>` upstairs) |
| Food court | Upper level, north arm. Four kiosks: Wok Express, Squeeze Juice Bar, Harbour Scoops and a Dockside Burgers branch. Each has a counter with an order board, cooking stations and a menu board with prices. Seating for 64, and a staff supplies counter (the Food Wholesaler). Run by FoodService like the other food businesses |
| Mall Management | South arm, ground floor. Desks to take the Mall Cleaner and Mall Security jobs |
| Cleaner job | While a cleaner is on shift, litter (cans, packets, spills, newspapers) builds up around both floors, up to 10 pieces. "Clean up" pays each time |
| Security job | 7 numbered checkpoints across both floors. Check in at them in order (1 to 7, then round again); each correct check-in pays |
| NPC shoppers | Up to 16 at a time, only while a player is within 700 studs. They come in through the entrances (or the footbridge for the upper floor) and visit 1-3 stores. At each till they buy one item, which comes off that store's real stock, and they carry a bag out. Doors open for them |
| Car park | Ground plus 3 decks (12 studs each), painted bays, columns and a green pedestrian walkway. Stacked two-way ramps (7 degrees) with walls and barriers, and height bars at both entrances. A big P sign tower, lamp posts on the roof deck, and a lift to every deck |
| Footbridge | From the car park deck level with the mall's upper floor to the mall's east entrance tower |

## Store line-up (edit `MallDefinitions.stores` to change)

Ground floor: Grocery, Hardware, Furniture, Electronics, Pharmacy, Sports, Pet Store, Fishing Shop.
Level 1: Clothing, Shoe Shop, Jewellers, Bookshop, Toy Shop, Music Store, Gun Shop (clothing & display only), General Store.

Each entry sets `shop` (a ShopDefinitions id), `wall`/`floor`/`accent`/`signColor` colours, `floorMat`, `font`,
`layout` (aisles, racks, tables, showroom, tanks, wallShelves, cases, bookcases) and `features`
(produce, fridges, timber, shed, dispensary, rodWall, boat, mannequins, fittingRooms, ballPyramids, hoop,
displayCases, tvWall, guitarWall, stage, benches, giantTeddy, readingArea).
Sizes (floor height, concourse width, target store width, car park decks, ramp angle) are at the top of the file.
If the site is too small for 16 stores, they get narrower and a warning is printed in Output.

## Testing without your map

TestWorld (dev only) makes a test `MallSite` and `CarParkSite` north of the test floor, but only when the map has no
`MallSite`. Walk north from spawn, or drive a car up the ramps.
