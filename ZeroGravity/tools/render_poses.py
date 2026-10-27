#!/usr/bin/env python3
"""Pose sheet for the zero-g character animation, without Roblox Studio.

Runs the real CharacterAnimator and CharacterService (weapon mounting) on the mock R15 rig from
tests/mock.luau, solves the joints, and draws every body and weapon part as shaded boxes from a
three-quarter view into docs/animation/pose_sheet.png.

Usage:  python3 tools/render_poses.py [path-to-luau]
Requires matplotlib.
"""
import math
import os
import shutil
import subprocess
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "animation")

POSES = r'''
local CF, V3 = Mock.CFrame, Mock.Vector3
local Players = Mock.services.Players
local plr = Mock.addPlayer("Pilot", 99)
Players._props.LocalPlayer = plr
local cam = Mock.Instance.new("Camera")
cam.CFrame = CF.identity
Mock.workspace._props.CurrentCamera = cam
local CS = Mock.module("ServerScriptService", "Services", "CharacterService")
local State = Mock.module("StarterPlayer", "StarterPlayerScripts", "Controllers", "ClientState")
local Anim = Mock.module("StarterPlayer", "StarterPlayerScripts", "Controllers", "CharacterAnimator")
local Config = Mock.module("ReplicatedStorage", "Shared", "Config")
local M = Config.Movement

local function f(n) return string.format("%.3f", n) end
local CollectionService = Mock.services.CollectionService
local function pose(label, opts)
	-- gravity poses: a deck with artificial gravity around the origin (and a floor unless airborne)
	local zone, floor
	if opts.gravity then
		zone = Mock.Instance.new("Part")
		zone.Anchored, zone.CanCollide, zone.CanQuery, zone.Transparency = true, false, false, 1
		zone.Size, zone.CFrame = V3.new(200, 60, 200), CF.identity
		zone.Parent = Mock.workspace
		CollectionService:AddTag(zone, "GravityZone")
		if not opts.airborne then
			floor = Mock.Instance.new("Part")
			floor.Anchored, floor.Transparency, floor.Size = true, 1, V3.new(200, 1, 200)
			floor.CFrame = CF.new(0, -Config.Gravity.HipHeight - 0.5, 0)
			floor.Parent = Mock.workspace
		end
		Mock.advance(2.1) -- Gravity refreshes its zone list every 2 s
	end
	cam.CFrame = if opts.camPitch then CF.Angles(math.rad(opts.camPitch), 0, 0) else CF.identity
	local char = Mock.buildRig("Pilot", CF.identity)
	char.Parent = Mock.workspace
	plr._props.Character = char
	CS.ApplySuit(plr, char, "navy")
	if opts.weapon then CS.SetWeaponVisual(plr, opts.weapon, "epic") end
	local root = char.HumanoidRootPart
	State.Aiming = opts.aim == true
	local hum = char:FindFirstChildOfClass("Humanoid")
	if opts.dead then hum._props.Health = 0 end
	local function frame()
		root._props.CFrame = CF.identity
		root._props.AssemblyLinearVelocity = opts.vel or V3.zero
		Anim.StepAll(1 / 60)
		Mock.advance(1 / 60)
	end
	for _ = 1, math.floor((opts.settle or 1.5) * 60) do frame() end
	if opts.roll then
		Anim.Roll(1)
		for _ = 1, math.floor(M.RollTime * opts.roll * 60) do frame() end
	end
	if opts.reload then
		char:SetAttribute("ReloadTime", 2)
		char:SetAttribute("ReloadEnd", Mock.clock() + 2 * (1 - opts.reload))
		frame()
	end
	if opts.swap then
		CS.SetWeaponVisual(plr, opts.weapon, "epic")
		for _ = 1, math.floor(0.4 * opts.swap * 60) do frame() end
	end
	if opts.melee then
		char:SetAttribute("MeleeAt", Mock.clock())
		for _ = 1, math.floor(0.35 * opts.melee * 60) do frame() end
	end
	if opts.fire then
		Anim.Fired()
		frame()
	end
	root._props.CFrame = CF.identity
	Mock.solveJoints(char)
	if zone then zone:Destroy() end
	if floor then floor:Destroy() end
	print("POSE|" .. label)
	for _, p in char:GetDescendants() do
		local pr = p._props
		if p:IsA("BasePart") and pr.Transparency < 1 and pr.Name ~= "HumanoidRootPart" then
			local c, m = pr.CFrame, pr.CFrame.m
			local col = pr.Color or (pr.Name == "Head" and { R = 0.9, G = 0.78, B = 0.68 } or { R = 0.28, G = 0.36, B = 0.56 })
			local shape = pr.Shape and pr.Shape.Name or "Block"
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType and mesh.MeshType.Name == "Sphere" then shape = "Ellipsoid" end
			if pr.Name == "Head" then shape = "Ellipsoid" end -- Roblox heads are rounded meshes; the mock's is a box
			print(table.concat({ "P", pr.Name, shape, f(c.p.X), f(c.p.Y), f(c.p.Z), f(pr.Size.X), f(pr.Size.Y), f(pr.Size.Z),
				f(m[1]), f(m[2]), f(m[3]), f(m[4]), f(m[5]), f(m[6]), f(m[7]), f(m[8]), f(m[9]), f(col.R), f(col.G), f(col.B),
				f(pr.Transparency or 0) }, "|"))
		end
	end
	char:Destroy()
end

pose("Drifting (low ready)", { weapon = "assault" })
pose("Aiming", { weapon = "assault", aim = true })
pose("Firing (recoil)", { weapon = "assault", aim = true, fire = true })
pose("Flying forward", { weapon = "assault", vel = V3.new(0, 0, -40) })
pose("Boosting", { weapon = "assault", vel = V3.new(0, 0, -82) })
pose("Strafing right (bank)", { weapon = "assault", vel = V3.new(40, 0, 0) })
pose("Descending (tuck)", { weapon = "assault", vel = V3.new(0, -38, 0) })
pose("Reversing", { weapon = "assault", vel = V3.new(0, 0, 35) })
pose("Air roll 1/3", { weapon = "assault", roll = 0.33 })
pose("Air roll 2/3", { weapon = "assault", roll = 0.62 })
pose("Pistol, aiming", { weapon = "pistol", aim = true })
pose("Sniper, aiming", { weapon = "precision", aim = true })
pose("Reloading (magazine out)", { weapon = "assault", reload = 0.45 })
pose("Weapon swap (raising)", { weapon = "burst", swap = 0.35 })
pose("Melee strike", { weapon = "assault", melee = 0.5 })
pose("Unarmed punch", { melee = 0.5 })
pose("Gravity: standing", { weapon = "assault", gravity = true })
pose("Gravity: walking", { weapon = "assault", gravity = true, vel = V3.new(0, 0, -18), settle = 1.13 })
pose("Gravity: walking, unarmed", { gravity = true, vel = V3.new(0, 0, -18), settle = 1.0 })
pose("Gravity: aiming up 35°", { weapon = "assault", gravity = true, aim = true, camPitch = 35 })
pose("Gravity: jetpack / airborne", { weapon = "assault", gravity = true, airborne = true, vel = V3.new(0, 15, 0) })
pose("Unarmed drift", {})
pose("Unarmed boost", { vel = V3.new(0, 0, -82) })
pose("Eliminated (tumbling)", { dead = true, settle = 2.5 })
'''


def long_string(s):
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{s}]{eq}]"


def export(luau):
    sources = {}
    for base, _, files in os.walk(os.path.join(ROOT, "src")):
        for fn in files:
            if fn.endswith(".luau"):
                p = os.path.join(base, fn)
                sources[os.path.relpath(p, ROOT).replace(os.sep, "/")] = open(p, encoding="utf-8").read()
    parts = ["SOURCES = {"] + [f'["{k}"] = {long_string(v)},' for k, v in sorted(sources.items())] + ["}"]
    api = os.path.join(ROOT, "tests", "api", "roblox_api.luau")
    if os.path.exists(api):
        parts.append("ROBLOX_API = (function()\n" + open(api, encoding="utf-8").read() + "\nend)()")
    parts.append("local Mock = (function()\n" + open(os.path.join(ROOT, "tests", "mock.luau"), encoding="utf-8").read() + "\nend)()")
    parts.append(POSES)
    bundle = os.path.join(ROOT, "tests", ".bundle.luau")
    open(bundle, "w", encoding="utf-8").write("\n".join(parts))
    r = subprocess.run([luau, bundle], capture_output=True, text=True)
    os.remove(bundle)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit(1)
    return r.stdout.splitlines()


def parse(lines):
    poses = []
    for ln in lines:
        f = ln.split("|")
        if f[0] == "POSE":
            poses.append((f[1], []))
        elif f[0] == "P" and poses:
            v = list(map(float, f[3:22]))
            poses[-1][1].append({"name": f[1], "shape": f[2], "pos": v[0:3], "size": v[3:6], "m": v[6:15], "col": v[15:18], "alpha": 1 - v[18]})
    return poses


# three-quarter view from the front-right (the gun side), slightly above; the character looks along -Z
YAW, PITCH = math.radians(40), math.radians(-12)


def view(p):
    x, y, z = p
    # rotate about Y (yaw), then about X (pitch); camera looks along -Z of the result
    cx, sx = math.cos(YAW), math.sin(YAW)
    x, z = x * cx + z * sx, -x * sx + z * cx
    cp, sp = math.cos(PITCH), math.sin(PITCH)
    y, z = y * cp - z * sp, y * sp + z * cp
    return -x, y, z  # camera in front looking along +Z: the character's right side is on the viewer's left


FACES = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 5, 7, 6), (1, 0, 0)), ((0, 1, 5, 4), (0, -1, 0)), ((2, 3, 7, 6), (0, 1, 0)),
         ((0, 2, 6, 4), (0, 0, -1)), ((1, 3, 7, 5), (0, 0, 1))]
LIGHT = (0.4, 0.8, 0.45)


def sphere(part):
    c = view(part["pos"])
    r = part["size"][0] / 2
    pts = [(c[0] + r * math.cos(a / 16 * math.pi), c[1] + r * math.sin(a / 16 * math.pi)) for a in range(32)]
    return [(c[2], pts, 0.9)]


def ellipsoid(part):
    # silhouette = convex hull of the projected surface; shaded by the light on its centre-facing side
    (x, y, z), (sx, sy, sz), m = part["pos"], part["size"], part["m"]
    pts, depth = [], 0.0
    for i in range(9):
        th = math.pi * i / 8
        for j in range(16):
            ph = 2 * math.pi * j / 16
            lx, ly, lz = sx / 2 * math.sin(th) * math.cos(ph), sy / 2 * math.cos(th), sz / 2 * math.sin(th) * math.sin(ph)
            w = (x + m[0] * lx + m[1] * ly + m[2] * lz, y + m[3] * lx + m[4] * ly + m[5] * lz, z + m[6] * lx + m[7] * ly + m[8] * lz)
            v = view(w)
            pts.append((v[0], v[1]))
            depth += v[2]
    return [(depth / len(pts), hull2d(pts), 0.95)]


def hull2d(pts):
    pts = sorted(set(pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def cylinder(part):
    # axis along the part's X; silhouette = hull of both end circles
    (x, y, z), (sx, sy, sz), m = part["pos"], part["size"], part["m"]
    r = min(sy, sz) / 2
    pts, depth = [], 0.0
    for lx in (-sx / 2, sx / 2):
        for j in range(20):
            a = 2 * math.pi * j / 20
            ly, lz = r * math.cos(a), r * math.sin(a)
            v = view((x + m[0] * lx + m[1] * ly + m[2] * lz, y + m[3] * lx + m[4] * ly + m[5] * lz, z + m[6] * lx + m[7] * ly + m[8] * lz))
            pts.append((v[0], v[1]))
            depth += v[2]
    return [(depth / len(pts), hull2d(pts), 0.9)]


def boxes(part):
    if part["shape"] == "Ball":
        return sphere(part)
    if part["shape"] == "Cylinder":
        return cylinder(part)
    if part["shape"] == "Ellipsoid":
        return ellipsoid(part)
    (x, y, z), (sx, sy, sz), m = part["pos"], part["size"], part["m"]
    corners = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                lx, ly, lz = dx * sx, dy * sy, dz * sz
                corners.append((x + m[0] * lx + m[1] * ly + m[2] * lz, y + m[3] * lx + m[4] * ly + m[5] * lz, z + m[6] * lx + m[7] * ly + m[8] * lz))
    out = []
    for idx, n in FACES:
        wn = (m[0] * n[0] + m[1] * n[1] + m[2] * n[2], m[3] * n[0] + m[4] * n[1] + m[5] * n[2], m[6] * n[0] + m[7] * n[1] + m[8] * n[2])
        vn = view(wn)
        if vn[2] > 0:  # facing away from the viewer
            continue
        shade = 0.45 + 0.55 * max(0.0, wn[0] * LIGHT[0] + wn[1] * LIGHT[1] + wn[2] * LIGHT[2])
        pts = [view(corners[i]) for i in idx]
        depth = sum(p[2] for p in pts) / 4
        out.append((depth, [(p[0], p[1]) for p in pts], shade))
    return out


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("luau") or "/tmp/luau/luau")
    poses = parse(export(luau))
    os.makedirs(OUT, exist_ok=True)
    cols = 5
    rows = math.ceil(len(poses) / cols)
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 3.6, rows * 4.0))
    fig.patch.set_facecolor("#05070c")
    for ax in axes.flat:
        ax.set_facecolor("#0a0f1a")
        ax.set_xticks([])
        ax.set_yticks([])
        for s in ax.spines.values():
            s.set_color("#223344")
    for ax, (label, parts) in zip(axes.flat, poses):
        faces = []
        for p in parts:
            for depth, pts, shade in boxes(p):
                faces.append((depth, pts, tuple(min(1, c * shade) for c in p["col"]), p["alpha"]))
        faces.sort(key=lambda f: -f[0])  # far to near
        for _, pts, col, alpha in faces:
            ax.add_patch(Polygon(pts, closed=True, facecolor=col, edgecolor=(0, 0, 0, 0.5), lw=0.4, alpha=max(alpha, 0.35)))
        ax.set_xlim(-4.2, 4.2)
        ax.set_ylim(-4.6, 3.8)
        ax.set_aspect("equal")
        ax.set_title(label, color="white", fontsize=11)
    for ax in list(axes.flat)[len(poses):]:
        ax.set_visible(False)
    fig.suptitle("ZERO GRAVITY character animation (CharacterAnimator on an R15 rig): zero-g flight, then walking under station gravity - three-quarter view from the front right",
                 color="white", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 1 - 0.5 / (rows * 4.0)))
    path = os.path.join(OUT, "pose_sheet.png")
    fig.savefig(path, dpi=100)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
