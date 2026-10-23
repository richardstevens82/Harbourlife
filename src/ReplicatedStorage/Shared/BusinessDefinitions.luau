return {
	pizza_shop = {
		name = "Harbour Pizza",
		maxOpenOrders = 5,
		orderIntervalSeconds = 20,
		orderLifetimeSeconds = 120,
		counterMultiplier = 1.5, -- sale price = item price * multiplier
		deliveryMultiplier = 2.0,
		reputationOnServe = 1,
		reputationOnExpire = -2,
		minCookSeconds = 4,
	},
	-- Phase 5 food businesses, all run by FoodService.
	-- counter = Part name that serves orders (extra branches add "_<n>", e.g. FastFoodCounter_2); stations = Part name prefix -> appliance type
	-- (e.g. a Part "CafeCoffeeMachine_1"); jobs = jobs that count as staff; menu = recipes customers order.
	cafe = {
		food = true, name = "Harbour Café", counter = "CafeCounter", jobs = { "barista" },
		stations = { CafeCoffeeMachine = "coffee_machine", CafeToaster = "toaster" },
		menu = { "coffee", "tea", "toastie" },
		maxOpenOrders = 4, orderIntervalSeconds = 18, orderLifetimeSeconds = 120,
		counterMultiplier = 1.5, reputationOnServe = 1, reputationOnExpire = -2, minCookSeconds = 2,
	},
	bakery = {
		food = true, name = "Harbour Bakery", counter = "BakeryCounter", jobs = { "baker" },
		stations = { BakeryOven = "bakery_oven" },
		menu = { "bread", "croissant", "cupcake" },
		maxOpenOrders = 4, orderIntervalSeconds = 22, orderLifetimeSeconds = 150,
		counterMultiplier = 1.6, reputationOnServe = 1, reputationOnExpire = -2, minCookSeconds = 3,
	},
	restaurant = {
		food = true, name = "Quayside Restaurant", counter = "RestaurantCounter", jobs = { "chef", "waiter" },
		stations = { RestaurantStove = "stove" },
		menu = { "roast_chicken", "chicken_curry", "vegetable_soup" },
		maxOpenOrders = 5, orderIntervalSeconds = 25, orderLifetimeSeconds = 180,
		counterMultiplier = 1.8, reputationOnServe = 2, reputationOnExpire = -3, minCookSeconds = 5,
	},
	fast_food = {
		food = true, name = "Dockside Burgers", counter = "FastFoodCounter", jobs = { "fast_food_worker" },
		stations = { FastFoodGrill = "grill", FastFoodFryer = "fryer" },
		menu = { "burger", "fries", "nuggets" },
		maxOpenOrders = 6, orderIntervalSeconds = 12, orderLifetimeSeconds = 90,
		counterMultiplier = 1.4, reputationOnServe = 1, reputationOnExpire = -1, minCookSeconds = 2,
	},
	-- Harbour Mall food court kiosks (the court also has a second Dockside Burgers counter, FastFoodCounter_2)
	noodle_bar = {
		food = true, name = "Wok Express", counter = "NoodleCounter", jobs = { "chef", "fast_food_worker" },
		stations = { NoodleWok = "wok" },
		menu = { "noodles", "stir_fry", "spring_rolls" },
		maxOpenOrders = 5, orderIntervalSeconds = 16, orderLifetimeSeconds = 120,
		counterMultiplier = 1.5, reputationOnServe = 1, reputationOnExpire = -2, minCookSeconds = 2,
	},
	juice_bar = {
		food = true, name = "Squeeze Juice Bar", counter = "JuiceCounter", jobs = { "barista" },
		stations = { JuiceBlender = "blender" },
		menu = { "smoothie", "orange_juice" },
		maxOpenOrders = 4, orderIntervalSeconds = 18, orderLifetimeSeconds = 100,
		counterMultiplier = 1.6, reputationOnServe = 1, reputationOnExpire = -1, minCookSeconds = 1,
	},
	ice_cream = {
		food = true, name = "Harbour Scoops", counter = "IceCreamCounter", jobs = { "barista", "fast_food_worker" },
		stations = { IceCreamFreezer = "freezer" },
		menu = { "ice_cream_cone", "sundae", "milkshake" },
		maxOpenOrders = 5, orderIntervalSeconds = 14, orderLifetimeSeconds = 90,
		counterMultiplier = 1.5, reputationOnServe = 1, reputationOnExpire = -1, minCookSeconds = 1,
	},
}
