-- Server and client read this; only the server may change inventories.
-- price = base price; shops apply their own markup. stack = max held.
local function item(name, price, stack, category) return { name = name, price = price, stack = stack, category = category } end

return {
	-- food & ingredients
	pizza_dough = item("Pizza Dough", 2, 99, "food"),
	tomato_sauce = item("Tomato Sauce", 3, 99, "food"),
	cheese = item("Cheese", 4, 99, "food"),
	pizza = item("Pizza", 12, 10, "food"),
	bread = item("Bread", 3, 20, "food"),
	milk = item("Milk", 2, 20, "food"),
	apple = item("Apple", 1, 30, "food"),
	sandwich = item("Sandwich", 5, 10, "food"),
	water_bottle = item("Water Bottle", 1, 20, "food"),
	snack_bar = item("Snack Bar", 2, 20, "food"),
	-- general
	fuel_can = item("Fuel Can", 15, 5, "general"),
	torch = item("Torch", 15, 3, "general"),
	batteries = item("Batteries", 4, 20, "general"),
	town_map = item("Town Map", 5, 1, "general"),
	-- clothing
	tshirt = item("T-Shirt", 20, 3, "clothing"),
	jeans = item("Jeans", 35, 3, "clothing"),
	hoodie = item("Hoodie", 45, 3, "clothing"),
	work_boots = item("Work Boots", 50, 2, "clothing"),
	hi_vis_vest = item("Hi-Vis Vest", 25, 2, "clothing"),
	cap = item("Cap", 15, 3, "clothing"),
	-- electronics
	phone = item("Mobile Phone", 300, 1, "electronics"),
	radio = item("Radio", 80, 2, "electronics"),
	camera = item("Camera", 250, 1, "electronics"),
	laptop = item("Laptop", 900, 1, "electronics"),
	headphones = item("Headphones", 60, 2, "electronics"),
	-- hardware
	hammer = item("Hammer", 25, 2, "tools"),
	wrench = item("Wrench", 30, 2, "tools"),
	screwdriver = item("Screwdriver", 12, 2, "tools"),
	paint_tin = item("Paint Tin", 18, 10, "tools"),
	rope = item("Rope", 10, 5, "tools"),
	toolbox = item("Toolbox", 70, 1, "tools"),
	planks = item("Wooden Planks", 8, 50, "materials"),
	nails = item("Box of Nails", 3, 20, "materials"),
	-- fishing
	fishing_rod = item("Fishing Rod", 60, 1, "fishing"),
	bait = item("Bait", 2, 50, "fishing"),
	tackle_box = item("Tackle Box", 40, 1, "fishing"),
	landing_net = item("Landing Net", 35, 1, "fishing"),
	cool_box = item("Cool Box", 45, 1, "fishing"),
	-- furniture (placed in homes in the Property phase)
	chair = item("Chair", 40, 4, "furniture"),
	table = item("Table", 90, 2, "furniture"),
	sofa = item("Sofa", 300, 1, "furniture"),
	bed = item("Bed", 400, 1, "furniture"),
	lamp = item("Lamp", 35, 4, "furniture"),
	rug = item("Rug", 60, 2, "furniture"),
	-- pets (live pets arrive with the pet system; these are supplies and pet clothes)
	pet_food = item("Pet Food", 6, 20, "pets"),
	pet_bed = item("Pet Bed", 40, 1, "pets"),
	pet_collar = item("Pet Collar", 15, 3, "pets"),
	pet_jumper = item("Pet Jumper", 20, 3, "pets"),
	pet_hat = item("Pet Hat", 12, 3, "pets"),
	pet_toy = item("Pet Toy", 8, 5, "pets"),
	-- gun shop: clothing and display items only (developer decision, no functional weapons)
	camo_jacket = item("Camo Jacket", 60, 2, "clothing"),
	cargo_trousers = item("Cargo Trousers", 40, 2, "clothing"),
	tactical_boots = item("Tactical Boots", 70, 2, "clothing"),
	range_cap = item("Range Cap", 15, 3, "clothing"),
	ear_defenders = item("Ear Defenders", 25, 2, "clothing"),
	display_case = item("Display Case (decor)", 120, 1, "furniture"),
}
