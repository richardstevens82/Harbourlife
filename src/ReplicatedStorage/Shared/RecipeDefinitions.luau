-- station = the appliance type that cooks it (see BusinessDefinitions food businesses).
-- cookSeconds is reduced by cooking skill down to the business's minCookSeconds.
return {
	pizza = {
		output = "pizza",
		inputs = { pizza_dough = 1, tomato_sauce = 1, cheese = 1 },
		cookSeconds = 10, -- reduced by cooking skill, see PizzaService
	},
	-- café
	coffee = { output = "coffee", inputs = { coffee_beans = 1, milk = 1 }, cookSeconds = 5, station = "coffee_machine" },
	tea = { output = "tea", inputs = { tea_leaves = 1, milk = 1 }, cookSeconds = 4, station = "coffee_machine" },
	toastie = { output = "toastie", inputs = { bread = 1, cheese = 1, butter = 1 }, cookSeconds = 6, station = "toaster" },
	-- bakery
	bread = { output = "bread", inputs = { flour = 2 }, cookSeconds = 8, station = "bakery_oven" },
	croissant = { output = "croissant", inputs = { flour = 1, butter = 1 }, cookSeconds = 7, station = "bakery_oven" },
	cupcake = { output = "cupcake", inputs = { flour = 1, sugar = 1, eggs = 1 }, cookSeconds = 7, station = "bakery_oven" },
	-- restaurant
	roast_chicken = { output = "roast_chicken", inputs = { chicken = 1, vegetables = 1, potatoes = 1 }, cookSeconds = 14, station = "stove" },
	chicken_curry = { output = "chicken_curry", inputs = { chicken = 1, rice = 1 }, cookSeconds = 12, station = "stove" },
	vegetable_soup = { output = "vegetable_soup", inputs = { vegetables = 2 }, cookSeconds = 9, station = "stove" },
	-- fast food
	burger = { output = "burger", inputs = { beef_patty = 1, burger_bun = 1, lettuce = 1 }, cookSeconds = 6, station = "grill" },
	fries = { output = "fries", inputs = { potatoes = 1, cooking_oil = 1 }, cookSeconds = 5, station = "fryer" },
	nuggets = { output = "nuggets", inputs = { chicken = 1, cooking_oil = 1 }, cookSeconds = 6, station = "fryer" },
	-- mall food court
	noodles = { output = "noodles", inputs = { noodle_pack = 1, vegetables = 1 }, cookSeconds = 6, station = "wok" },
	stir_fry = { output = "stir_fry", inputs = { chicken = 1, vegetables = 1, rice = 1 }, cookSeconds = 8, station = "wok" },
	spring_rolls = { output = "spring_rolls", inputs = { vegetables = 1, flour = 1, cooking_oil = 1 }, cookSeconds = 6, station = "wok" },
	smoothie = { output = "smoothie", inputs = { strawberries = 1, bananas = 1, milk = 1 }, cookSeconds = 4, station = "blender" },
	orange_juice = { output = "orange_juice", inputs = { oranges = 2 }, cookSeconds = 3, station = "blender" },
	ice_cream_cone = { output = "ice_cream_cone", inputs = { ice_cream_mix = 1, wafer_cone = 1 }, cookSeconds = 3, station = "freezer" },
	sundae = { output = "sundae", inputs = { ice_cream_mix = 1, strawberries = 1, sugar = 1 }, cookSeconds = 4, station = "freezer" },
	milkshake = { output = "milkshake", inputs = { ice_cream_mix = 1, milk = 1 }, cookSeconds = 4, station = "freezer" },
}
