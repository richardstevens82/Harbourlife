-- markup multiplies the item's base price. stock = max units held; restock adds 1 of each item per interval.
-- Any Part named "Shop_<id>" becomes a counter for that shop (several locations may share one id).
return {
	grocery = { name = "Grocery", markup = 1.0, stock = 20, restockSeconds = 30,
		items = { "bread", "milk", "apple", "cheese", "tomato_sauce", "pizza_dough", "water_bottle", "sandwich" } },
	general_store = { name = "General Store", markup = 1.2, stock = 10, restockSeconds = 45,
		items = { "water_bottle", "snack_bar", "torch", "batteries", "fuel_can", "town_map" } },
	clothing = { name = "Clothing Store", markup = 1.0, stock = 6, restockSeconds = 60,
		items = { "tshirt", "jeans", "hoodie", "work_boots", "hi_vis_vest", "cap" } },
	electronics = { name = "Electronics", markup = 1.0, stock = 3, restockSeconds = 120,
		items = { "phone", "radio", "camera", "laptop", "headphones" } },
	hardware = { name = "Hardware Store", markup = 1.0, stock = 10, restockSeconds = 45,
		items = { "hammer", "wrench", "screwdriver", "paint_tin", "rope", "toolbox", "planks", "nails" } },
	fishing_shop = { name = "Fishing Shop", markup = 1.0, stock = 6, restockSeconds = 60,
		items = { "fishing_rod", "bait", "tackle_box", "landing_net", "cool_box" } },
	furniture = { name = "Furniture Store", markup = 1.0, stock = 4, restockSeconds = 90,
		items = { "chair", "table", "sofa", "bed", "lamp", "rug" } },
	pet_store = { name = "Pet Store", markup = 1.0, stock = 8, restockSeconds = 60,
		items = { "pet_food", "pet_bed", "pet_collar", "pet_jumper", "pet_hat", "pet_toy" } },
	gun_shop = { name = "Gun Shop (Clothing & Display)", markup = 1.0, stock = 5, restockSeconds = 60,
		items = { "camo_jacket", "cargo_trousers", "tactical_boots", "range_cap", "ear_defenders", "display_case" } },
}
