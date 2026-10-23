# Harbourlife: install the mall and new systems into Studio (instructions for Claude Code)

You are Claude Code, running on the developer's Windows PC with the **Roblox Studio MCP server** connected
(`claude mcp add --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"`).
Use the MCP tool that runs Luau in Studio (usually `run_code`) for every Studio change.
The developer's town map is the place currently open in Studio. This repository holds the scripts; the map is not in it.

Work through the steps in order. Stop and ask the developer whenever a step says **ASK**.
Never delete anything from their map. Move it into `ServerStorage.RemovedForMall` so it can be put back.

---

## What you are installing

All source is in `src/`. It was written and checked offline but has **never run in Studio**, so expect to fix things.

| Add-on | Files | What it does |
|---|---|---|
| Phase 5 food businesses | `FoodService`, `BusinessDefinitions`, `RecipeDefinitions`, `ItemDefinitions`, `JobDefinitions`, `ShopDefinitions` | Café, bakery, restaurant and fast food, run by one data-driven loop. Food Wholesaler supplier, cooking stations, customer orders with counter boards, pay, XP and reputation. Jobs: barista, baker, chef, waiter, fast food worker |
| Harbour Mall building | `MallBuilder`, `MallDefinitions` | Built to fit a `MallSite` Part and a `CarParkSite` Part. Two levels with stone cladding and bronze/glass entrance towers. Skylit atrium, 4 escalators, 3 glass lifts, stairs, directories, ATMs and toilets. 16 themed stores (till, stockroom, staff room, loading door). Multi-storey car park with ramps, and a footbridge |
| Mall runtime | `MallService` | Builds the mall at startup if it isn't baked in. Runs lifts, escalator conveyors, 21 automatic sliding doors and ATMs |
| Moving escalator steps | `EscalatorVisuals` (LocalScript) | Step edges drawn on each player's screen, moving along the conveyors |
| Food court | `MallBuilder` + `BusinessDefinitions` | Upper north arm. Wok Express, Squeeze Juice Bar, Harbour Scoops and a Dockside Burgers branch, with seating and a staff supplies counter |
| Mall jobs | `MallJobService`, `JobDefinitions` | Mall Cleaner (litter appears while a cleaner is on shift) and Mall Security (7 checkpoints visited in order). Sign up at the Mall Management desks |
| NPC shoppers | `ShopperService`, `ShopService` (`NpcBuy`) | Up to 16 shoppers. They enter, visit stores, buy real stock, carry bags and leave. Doors open for them |
| 7 new stores | `ShopDefinitions`, `ItemDefinitions` | Pharmacy, sports, shoes, jewellers, books, toys, music |

Human-readable details: `docs/MallSetup.md`, `docs/PizzaBusinessSetup.md`.

---

## Step 0: Safety first

1. **ASK** the developer to save the place and keep a backup copy (File → Save to File As…) before you change anything.
2. Use `run_code` to check what is already there:
   ```lua
   local out = {}
   for _, path in { "ServerScriptService", "ReplicatedStorage", "StarterPlayer.StarterPlayerScripts" } do
       local inst = game
       for part in path:gmatch("[^.]+") do inst = inst:FindFirstChild(part) or game:GetService(part) end
       for _, d in inst:GetDescendants() do
           if d:IsA("LuaSourceContainer") then table.insert(out, d:GetFullName() .. " (" .. d.ClassName .. ", " .. #d.Source .. " chars)") end
       end
   end
   print(table.concat(out, "\n"))
   ```
   Note any scripts the developer wrote themselves (anything not in the table in Step 1). Never overwrite or delete those.

---

## Step 1: Copy every script into Studio

Studio can't read files from disk, so send each file's text through `run_code`.

### Where each file goes

| Repo file | Studio location | Class |
|---|---|---|
| `src/ReplicatedStorage/Shared/<Name>.luau` | `ReplicatedStorage.Shared.<Name>` (Folder `Shared`) | ModuleScript |
| `src/ServerScriptService/Systems/<Name>.luau` | `ServerScriptService.Systems.<Name>` (Folder `Systems`) | ModuleScript |
| `src/ServerScriptService/Main.server.luau` | `ServerScriptService.Main` | Script |
| `src/StarterPlayer/StarterPlayerScripts/<Name>.client.luau` | `StarterPlayer.StarterPlayerScripts.<Name>` | LocalScript |

The instance name is the file name without `.luau`, `.server.luau` or `.client.luau`. Copy **all** files in `src/`, not
just the new ones, because existing files changed too (ShopService, FoodService, ItemDefinitions, Main, …).
New files in this update: `MallDefinitions`, `MallBuilder`, `MallService`, `MallJobService`, `ShopperService`, `EscalatorVisuals`.

### How to send a file

Create or replace the instance, then set `Source`. Wrap the text in a long-bracket string whose level does not
appear in the file. Check for `]==]`; none of the current files contain it, so `[==[ … ]==]` is safe.

```lua
local function ensure(parent, name, class)
    local s = parent:FindFirstChild(name)
    if s and s.ClassName ~= class then s.Parent = game:GetService("ServerStorage"); s = nil end -- park, never destroy
    if not s then s = Instance.new(class); s.Name = name; s.Parent = parent end
    return s
end
local folder = game.ServerScriptService:FindFirstChild("Systems") or Instance.new("Folder")
folder.Name = "Systems"; folder.Parent = game.ServerScriptService
local s = ensure(folder, "MallService", "ModuleScript")
s.Source = [==[
-- paste the exact file contents here
]==]
print(s:GetFullName(), #s.Source)
```

**Large files:** `MallBuilder.luau` is about 72 KB. Send it in pieces of about 15 KB, split at line breaks.
- First call: `s.Source = [==[<chunk 1>]==]`.
- Each later call: `s.Source ..= [==[<chunk n>]==]`.
- A long-bracket string drops a newline that comes straight after `[==[`. So start every later chunk with a blank line if the split fell between lines, or the two lines will be joined.

**Check after each file:** the printed `#s.Source` must equal the file's size in bytes, give or take one trailing
newline. If it doesn't, resend the file.

`ScriptEditorService:UpdateSourceAsync` also works if setting `Source` directly is refused.

### Then check the whole set

```lua
local need = {
    Shared = { "BusinessDefinitions", "Config", "ItemDefinitions", "JobDefinitions", "MallDefinitions", "RecipeDefinitions",
        "Remotes", "ShopDefinitions", "SkillDefinitions", "VehicleDefinitions" },
    Systems = { "DataService", "EconomyService", "ExcavatorService", "FoodService", "InteractionService", "InventoryService",
        "JobCentre", "JobService", "MallBuilder", "MallJobService", "MallService", "NotificationService", "PizzaService",
        "ProgressionService", "ShopService", "ShopperService", "TestWorld", "VehicleService" },
    StarterPlayerScripts = { "EscalatorVisuals", "HUD", "ShopUI", "VehicleDriver" },
}
local roots = { Shared = game.ReplicatedStorage.Shared, Systems = game.ServerScriptService.Systems,
    StarterPlayerScripts = game.StarterPlayer.StarterPlayerScripts }
for k, list in need do
    for _, n in list do
        if not roots[k]:FindFirstChild(n) then warn("MISSING " .. k .. "." .. n) end
    end
end
print("Main:", game.ServerScriptService:FindFirstChild("Main") ~= nil)
```

### TestWorld

`TestWorld` builds dev test pads (job centre, pizza shop, food businesses, vehicle pads) and a test floor near the
world origin. It also builds a test mall site if the map has no `MallSite`.
**ASK** the developer whether their town already has these places. If they don't want the test pads in their town,
set `local TestWorld = { Enabled = false }` at the top of `TestWorld`. Tell them which systems then have no Parts
in their map yet. The list of Part names is in `docs/PizzaBusinessSetup.md`.

---

## Step 2: Mark the mall and car park sites

The developer drew the layout on their map:
- **Mall:** 2 × 2 city blocks, including the road that crossed between them.
- **Car park:** 1 × 2 blocks directly beside the mall, with one road between the car park and the mall.

1. **ASK** the developer to select, in Studio, everything inside the mall area (drag-select the ground, roads and
   buildings there). Then read the selection's bounds:
   ```lua
   local sel = game:GetService("Selection"):Get()
   local min, max = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
   for _, o in sel do
       local cf, size
       if o:IsA("BasePart") then cf, size = o.CFrame, o.Size elseif o:IsA("Model") then cf, size = o:GetBoundingBox() end
       if cf then
           local h = size / 2
           for _, sx in { -1, 1 } do for _, sy in { -1, 1 } do for _, sz in { -1, 1 } do
               local p = cf * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
               min = min:Min(p); max = max:Max(p)
           end end end
       end
   end
   print("min", min, "max", max, "size", max - min)
   ```
   Repeat for the car park area. Show the developer the sizes and positions and get their OK.
   If they'd rather type coordinates, use those instead.
2. Find the ground height: raycast down at the centre of each area. Use the road surface, not the top of a building.
3. **ASK** before clearing the areas. List what is inside each area: Parts and Models whose position falls within
   the bounds, excluding Terrain. Move the approved items into a Folder `ServerStorage.RemovedForMall`.
   **Leave the road between the mall and the car park.**
4. Create the two site Parts. Each is anchored, 1 stud thick, with its top surface on the ground, covering its area:
   ```lua
   local function site(name, centreXZ, sizeXZ, groundY)
       local p = workspace:FindFirstChild(name) or Instance.new("Part")
       p.Name = name; p.Anchored = true
       p.Size = Vector3.new(sizeXZ.X, 1, sizeXZ.Y)
       p.CFrame = CFrame.new(centreXZ.X, groundY - 0.5, centreXZ.Y)
       p.Transparency = 0.5; p.Parent = workspace
       return p
   end
   -- site("MallSite", Vector2.new(cx, cz), Vector2.new(sx, sz), groundY)
   -- site("CarParkSite", Vector2.new(cx, cz), Vector2.new(sx, sz), groundY)
   ```
   - If the town is rotated, give the Parts the same Y rotation. The builder follows the `MallSite`'s rotation, and turns the mall so its footbridge faces `CarParkSite`.
   - The mall needs about 400 × 400 studs or more to fit all 16 stores comfortably. On a smaller site the stores get narrower, and a warning is printed.

---

## Step 3: Build the mall into the place

Bake it, so it is ordinary Parts the developer can see and edit:

```lua
local mod = game.ServerScriptService.Systems.MallBuilder
local copy = mod:Clone() -- a fresh copy, so require() can't hand back an old cached version
copy.Parent = mod.Parent
local ok, res = pcall(function() return require(copy).Build(true) end)
copy:Destroy()
print(ok, res)
```

- `Build(true)` replaces any existing `HarbourMall` model, so it is safe to run again after changes.
- If it errors, read the message, fix the source (in the repo **and** in Studio), and run it again.

Check the result:

```lua
local mall = workspace:FindFirstChild("HarbourMall")
local CS = game:GetService("CollectionService")
local parts, tills = 0, {}
for _, d in mall:GetDescendants() do
    if d:IsA("BasePart") then parts += 1 end
    if d:IsA("BasePart") and d.Name:match("^Shop_") then table.insert(tills, d.Name) end
end
print("parts", parts, "tills", #tills)            -- expect about 9,700 and 17 (16 stores + Shop_food_wholesale)
print("doors", #CS:GetTagged("HarbourAutoDoor"))  -- 21
print("escalators", #CS:GetTagged("HarbourEscalator"), "lifts", #CS:GetTagged("HarbourElevator")) -- 4, 3
print("nodes", #mall.Nodes:GetChildren())         -- about 114
```

Then:
- **ASK** the developer to look around the mall in Studio. Fix anything that looks wrong, for example the skylight's glass end pieces facing the wrong way (Known Issue 9).
- Recommend `Workspace.StreamingEnabled = true` (the mall is about 9,700 parts). Ask before changing it.
- Have the developer save the place.

---

## Step 4: Play-test with the developer

The developer presses Play (you can't). Ask them to work through this list and report back, then fix what fails.
Ask them to paste anything red from the Output window.

| # | Test | Expected |
|---|---|---|
| 1 | Output on start | `[Harbourlife] server started`, and no `failed to start` lines |
| 2 | Walk up to any entrance or store door | Glass doors slide open, then close behind you |
| 3 | Ride an up escalator and a down escalator | Carried along. Yellow step edges move |
| 4 | Click CALL at a lift, then a floor button inside | Car comes, gate opens at the floor, carries you |
| 5 | Stairs in the north and south arms | Walkable to the upper level |
| 6 | Browse at a store till (`Shop_<id>`) and buy | Shop window opens, cash goes down, item in inventory (press I) |
| 7 | ATM (E deposit, F withdraw) | Cash and bank change by $100 |
| 8 | Food court: take the barista job (Job Centre pad), buy ingredients at STAFF SUPPLIES, use a blender, serve at the Juice counter | Order board updates, you get paid |
| 9 | Mall Management desk: take Mall Cleaner, wait about 12 s | Litter appears, Clean up pays |
| 10 | Take Mall Security (level 2 needed), check in at checkpoint 1, then 2 | Pays each time; the wrong order is refused |
| 11 | Stand in the mall for a minute | NPC shoppers come in, doors open for them, they visit tills and leave with bags |
| 12 | Drive a car into the car park and up the ramps | Reaches every deck; footbridge at the deck level with the mall's upper floor |
| 13 | Two players (Test → Clients and Servers) | Doors, lifts and stock behave the same for both |

---

## Step 5: Record the results

- Update `docs/HarbourlifeBuildProgress.md`. Mark a system complete **only** if it passed in Play Mode.
- Record every bug in `docs/HarbourlifeKnownIssues.md`, fixed or not.
- Copy any fix you made in Studio back into the matching repo file, so the repo and the place stay identical.
- Commit and push to the developer's branch.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `X failed to start` in Output | Read the error that follows. A missing module usually means a file wasn't copied (re-run the check in Step 1) |
| `require` returns old code in edit mode | Use the clone-and-require snippet in Step 3 |
| Mall faces the wrong way | `CarParkSite` isn't beside `MallSite`; move it, then rebuild |
| Stores missing, with "no room for …" warnings | `MallSite` is too small. Enlarge it, or lower `unitWidth` in `MallDefinitions`, then rebuild |
| Escalators don't move players | The conveyor velocity is set at runtime by MallService; check MallService started. Speed is `escalatorSpeed` in MallDefinitions |
| Lift car falls or jitters | Check the `Lift` PrismaticConstraint servo settings in `MallBuilder` (`buildElevator`). The car must be unanchored and welded parts massless |
| Shoppers stand still | Usually the R15 rig or animation load failed (Output shows `[ShopperService]`). The fallback block rig still walks. Pathfinding failures make them leave early |
| Doors never close | A player or NPC is within 11 studs. The radius is `DOOR_RADIUS` in MallService |

---

## House rules (from the master spec)

- Server authority: the server owns money, stock, jobs and rewards; never trust client values.
- No pay-to-win and no survival mechanics. The gun shop sells clothing and display items only.
- One system at a time: build, test, fix, test again, document, and only then mark complete.
- Don't claim something works until it has been seen working in Play Mode.
