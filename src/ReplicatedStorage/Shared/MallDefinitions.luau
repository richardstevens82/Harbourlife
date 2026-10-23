-- Harbour Mall: retail stores only. MallBuilder fits the building to a Part named "MallSite"
-- and the multi-storey car park to a Part named "CarParkSite" (see docs/MallSetup.md).
-- Stores fill units in order: ground floor first (north side west->east, then south side), then level 1.
-- Each store: shop = ShopDefinitions id, colours, floor material, sign font, interior layout and extra features.
local rgb = Color3.fromRGB

return {
	name = "HARBOUR MALL",
	floorHeight = 24, -- per mall level; must be a multiple of carParkDeckHeight so the bridge lines up
	concourseWidth = 48,
	galleryWidth = 12, -- upper-level walkway in front of the stores, either side of the atrium
	unitWidth = 100, -- target store frontage; the real width is fitted to the site
	salesFraction = 0.6, -- front share of each store that is shop floor; the rest is stockroom and staff room
	escalatorSpeed = 8,
	carParkDeckHeight = 12,
	carParkLevels = 4, -- ground + 3 decks
	carParkRampWidth = 28,
	carParkRampDegrees = 7,

	-- look taken from the developer's reference photos: stone cladding, bronze-framed glass entrance towers,
	-- blue LED band, glass skylight over the atrium, glass balustrades, cream marble with dark inlay bands
	structure = {
		exterior = rgb(222, 206, 178), exteriorDark = rgb(196, 178, 150), bronze = rgb(128, 92, 58), led = rgb(40, 110, 255),
		floor = rgb(236, 230, 218), inlay = rgb(70, 66, 62), gallery = rgb(240, 238, 232), ceiling = rgb(248, 247, 243),
		glass = rgb(150, 195, 225), metal = rgb(185, 188, 195), dark = rgb(55, 57, 62), planter = rgb(180, 165, 140),
		leaves = rgb(80, 130, 60), deck = rgb(120, 120, 124), lines = rgb(245, 245, 245),
	},

	-- food court on the upper level of the north arm: kiosks run by FoodService (see BusinessDefinitions)
	foodCourt = {
		{ biz = "noodle_bar", side = -1, z = 112, accent = rgb(200, 30, 40), counter = "NoodleCounter", stations = { "NoodleWok_1", "NoodleWok_2" } },
		{ biz = "juice_bar", side = -1, z = 142, accent = rgb(250, 150, 20), counter = "JuiceCounter", stations = { "JuiceBlender_1", "JuiceBlender_2" } },
		{ biz = "ice_cream", side = 1, z = 112, accent = rgb(240, 130, 190), counter = "IceCreamCounter", stations = { "IceCreamFreezer_1", "IceCreamFreezer_2" } },
		{ biz = "fast_food", side = 1, z = 142, accent = rgb(230, 180, 0), counter = "FastFoodCounter_2", stations = { "FastFoodGrill_21", "FastFoodFryer_21" } },
	},

	stores = {
		-- ground floor: bulky goods and big footprints
		{ shop = "grocery", wall = rgb(236, 244, 232), floor = rgb(210, 214, 206), floorMat = "Marble", accent = rgb(40, 140, 70),
			signColor = rgb(255, 255, 255), font = "GothamBold", layout = "aisles", shelfHeight = 6,
			products = { rgb(230, 80, 60), rgb(250, 200, 60), rgb(120, 190, 80), rgb(240, 140, 50), rgb(200, 60, 90) },
			features = { "produce", "fridges" } },
		{ shop = "hardware", wall = rgb(90, 92, 98), floor = rgb(150, 150, 150), floorMat = "Concrete", accent = rgb(240, 120, 20),
			signColor = rgb(20, 20, 20), font = "SourceSansBold", layout = "aisles", shelfHeight = 9,
			products = { rgb(240, 120, 20), rgb(60, 60, 60), rgb(200, 170, 110), rgb(30, 90, 170), rgb(180, 40, 40) },
			features = { "timber", "shed" } },
		{ shop = "furniture", wall = rgb(238, 228, 212), floor = rgb(150, 105, 70), floorMat = "WoodPlanks", accent = rgb(120, 80, 50),
			signColor = rgb(255, 245, 225), font = "Garamond", layout = "showroom",
			products = { rgb(110, 130, 150), rgb(190, 160, 120), rgb(160, 70, 60), rgb(90, 120, 90), rgb(230, 220, 200) } },
		{ shop = "electronics", wall = rgb(28, 30, 38), floor = rgb(45, 48, 58), floorMat = "SmoothPlastic", accent = rgb(0, 200, 255),
			signColor = rgb(0, 230, 255), font = "Arcade", layout = "tables",
			products = { rgb(20, 20, 24), rgb(200, 200, 210), rgb(0, 160, 255), rgb(255, 60, 120) },
			features = { "tvWall" } },
		{ shop = "pharmacy", wall = rgb(250, 252, 250), floor = rgb(225, 235, 230), floorMat = "Marble", accent = rgb(0, 160, 90),
			signColor = rgb(255, 255, 255), font = "Gotham", layout = "aisles", shelfHeight = 5,
			products = { rgb(255, 255, 255), rgb(120, 200, 230), rgb(250, 160, 180), rgb(0, 160, 90) },
			features = { "dispensary" } },
		{ shop = "sports", wall = rgb(30, 30, 30), floor = rgb(60, 140, 70), floorMat = "Fabric", accent = rgb(220, 30, 40),
			signColor = rgb(255, 255, 255), font = "LuckiestGuy", layout = "racks",
			products = { rgb(220, 30, 40), rgb(255, 255, 255), rgb(30, 90, 200), rgb(255, 210, 0) },
			features = { "ballPyramids", "hoop" } },
		{ shop = "pet_store", wall = rgb(200, 240, 235), floor = rgb(240, 220, 150), floorMat = "Pebble", accent = rgb(0, 150, 150),
			signColor = rgb(255, 230, 80), font = "FredokaOne", layout = "tanks",
			products = { rgb(255, 170, 60), rgb(120, 200, 255), rgb(240, 90, 120), rgb(140, 200, 90) } },
		{ shop = "fishing_shop", wall = rgb(28, 50, 80), floor = rgb(200, 180, 140), floorMat = "WoodPlanks", accent = rgb(230, 190, 120),
			signColor = rgb(28, 50, 80), font = "Bangers", layout = "aisles", shelfHeight = 6,
			products = { rgb(40, 110, 70), rgb(230, 120, 30), rgb(200, 200, 200), rgb(30, 60, 120) },
			features = { "rodWall", "boat" } },
		-- level 1: fashion and specialist
		{ shop = "clothing", wall = rgb(250, 236, 240), floor = rgb(240, 240, 240), floorMat = "Marble", accent = rgb(230, 120, 160),
			signColor = rgb(255, 255, 255), font = "Bodoni", layout = "racks",
			products = { rgb(240, 160, 190), rgb(250, 250, 250), rgb(60, 60, 80), rgb(170, 200, 230), rgb(230, 200, 120) },
			features = { "mannequins", "fittingRooms" } },
		{ shop = "shoes", wall = rgb(235, 220, 195), floor = rgb(120, 80, 55), floorMat = "Wood", accent = rgb(90, 55, 35),
			signColor = rgb(250, 235, 205), font = "Antique", layout = "wallShelves",
			products = { rgb(90, 55, 35), rgb(20, 20, 20), rgb(250, 250, 250), rgb(200, 60, 50) },
			features = { "benches" } },
		{ shop = "jewellery", wall = rgb(20, 20, 22), floor = rgb(30, 30, 32), floorMat = "Marble", accent = rgb(212, 175, 55),
			signColor = rgb(212, 175, 55), font = "Garamond", layout = "cases",
			products = { rgb(212, 175, 55), rgb(220, 220, 230), rgb(200, 30, 60), rgb(80, 160, 255) } },
		{ shop = "books", wall = rgb(110, 30, 40), floor = rgb(110, 75, 50), floorMat = "WoodPlanks", accent = rgb(60, 40, 30),
			signColor = rgb(240, 225, 190), font = "Merriweather", layout = "bookcases",
			products = { rgb(150, 30, 40), rgb(30, 60, 110), rgb(40, 100, 60), rgb(220, 200, 150), rgb(30, 30, 30) },
			features = { "readingArea" } },
		{ shop = "toys", wall = rgb(255, 240, 120), floor = rgb(120, 200, 255), floorMat = "Plastic", accent = rgb(255, 60, 60),
			signColor = rgb(255, 255, 255), font = "FredokaOne", layout = "tables",
			products = { rgb(255, 60, 60), rgb(60, 140, 255), rgb(60, 200, 90), rgb(255, 200, 0), rgb(200, 90, 255) },
			features = { "giantTeddy" } },
		{ shop = "music", wall = rgb(60, 30, 90), floor = rgb(35, 25, 45), floorMat = "WoodPlanks", accent = rgb(200, 90, 255),
			signColor = rgb(240, 200, 255), font = "PermanentMarker", layout = "tables",
			products = { rgb(180, 110, 60), rgb(20, 20, 20), rgb(240, 240, 240), rgb(200, 30, 30) },
			features = { "guitarWall", "stage" } },
		{ shop = "gun_shop", wall = rgb(85, 90, 60), floor = rgb(110, 95, 70), floorMat = "Slate", accent = rgb(190, 160, 100),
			signColor = rgb(230, 210, 160), font = "Oswald", layout = "racks",
			products = { rgb(85, 100, 60), rgb(150, 130, 90), rgb(60, 50, 40), rgb(200, 120, 40) },
			features = { "displayCases" } },
		{ shop = "general_store", wall = rgb(225, 235, 250), floor = rgb(200, 205, 215), floorMat = "SmoothPlastic", accent = rgb(30, 90, 200),
			signColor = rgb(255, 220, 40), font = "GothamBlack", layout = "aisles", shelfHeight = 6,
			products = { rgb(30, 90, 200), rgb(255, 220, 40), rgb(220, 80, 60), rgb(240, 240, 240) } },
	},
}
