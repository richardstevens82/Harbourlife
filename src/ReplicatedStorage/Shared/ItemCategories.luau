-- How item categories (ItemDefinitions .category) are shown in the inventory menu and on the phone.
local rgb = Color3.fromRGB

local info = {
	food = { name = "Food & Drink", icon = "🍔", color = rgb(235, 130, 50) },
	ingredient = { name = "Ingredients", icon = "🧂", color = rgb(200, 160, 90) },
	clothing = { name = "Clothing", icon = "👕", color = rgb(220, 90, 150) },
	jewellery = { name = "Jewellery", icon = "💍", color = rgb(212, 175, 55) },
	electronics = { name = "Electronics", icon = "📱", color = rgb(40, 160, 230) },
	tools = { name = "Tools", icon = "🔧", color = rgb(240, 120, 20) },
	materials = { name = "Materials", icon = "🪵", color = rgb(160, 120, 80) },
	fishing = { name = "Fishing", icon = "🎣", color = rgb(40, 110, 170) },
	sports = { name = "Sports", icon = "⚽", color = rgb(60, 170, 80) },
	health = { name = "Health", icon = "💊", color = rgb(0, 170, 120) },
	books = { name = "Books", icon = "📚", color = rgb(150, 40, 50) },
	toys = { name = "Toys", icon = "🧸", color = rgb(255, 90, 90) },
	music = { name = "Music", icon = "🎸", color = rgb(150, 80, 220) },
	furniture = { name = "Furniture", icon = "🛋️", color = rgb(130, 95, 70) },
	pets = { name = "Pets", icon = "🐾", color = rgb(0, 150, 150) },
	general = { name = "General", icon = "🎒", color = rgb(110, 120, 140) },
}

return {
	order = { "food", "ingredient", "clothing", "jewellery", "electronics", "tools", "materials", "fishing", "sports",
		"health", "books", "toys", "music", "furniture", "pets", "general" },
	info = info,
	-- anything with an unknown category is shown under General
	get = function(category: string?)
		return info[category or "general"] or info.general
	end,
}
