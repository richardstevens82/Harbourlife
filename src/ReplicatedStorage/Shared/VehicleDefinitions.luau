-- price 0 = starter vehicle. size is (width, height, length); the vehicle faces -Z.
return {
	sedan = { name = "Sedan", price = 0, size = Vector3.new(7, 2, 14), color = Color3.fromRGB(60, 100, 200),
		fuelCapacity = 60, fuelPerSecond = 0.15, wearPerSecond = 0.01, maxSpeed = 60, turnRate = 1.6 },
	pickup = { name = "Pickup", price = 1500, size = Vector3.new(8, 3, 16), color = Color3.fromRGB(180, 60, 50),
		fuelCapacity = 80, fuelPerSecond = 0.2, wearPerSecond = 0.012, maxSpeed = 55, turnRate = 1.5 },
	delivery_van = { name = "Delivery Van", price = 2500, size = Vector3.new(8, 4.5, 17), color = Color3.fromRGB(240, 240, 240),
		fuelCapacity = 90, fuelPerSecond = 0.22, wearPerSecond = 0.012, maxSpeed = 50, turnRate = 1.4 },
	excavator = { name = "Excavator", price = 8000, size = Vector3.new(10, 3, 12), color = Color3.fromRGB(240, 190, 30),
		fuelCapacity = 120, fuelPerSecond = 0.3, wearPerSecond = 0.02, maxSpeed = 18, turnRate = 1.0, construction = true },
}
