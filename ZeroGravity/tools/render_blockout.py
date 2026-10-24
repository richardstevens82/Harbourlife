#!/usr/bin/env python3
"""Blockout inspection without Roblox Studio: runs the real world builders inside the headless
Roblox mock (tests/mock.luau), exports every part / terrain fill / marker, and renders
orthographic plan and elevation views to docs/blockout/*.png.

Usage:  python3 tools/render_blockout.py [path-to-luau]
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
from matplotlib.patches import Circle, Polygon  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "blockout")

EXPORT = r'''
local WorldBuilder = Mock.module("ServerScriptService", "Services", "WorldBuilder")
WorldBuilder.Start()
local function f(n) return string.format("%.2f", n) end
for _, p in Mock.allParts do
	local pr = p._props
	if pr.Parent and not pr.Destroyed and pr.ClassName ~= "Terrain" and pr.Transparency < 1 then
		local c = pr.CFrame
		local m = c.m
		local col = pr.Color or { R = 0.6, G = 0.6, B = 0.6 }
		local shape = pr.Shape and pr.Shape.Name or "Block"
		print(table.concat({ "P", pr.Name, shape, f(c.p.X), f(c.p.Y), f(c.p.Z), f(pr.Size.X), f(pr.Size.Y), f(pr.Size.Z),
			f(m[1]), f(m[2]), f(m[3]), f(m[4]), f(m[5]), f(m[6]), f(m[7]), f(m[8]), f(m[9]),
			f(col.R), f(col.G), f(col.B), f(pr.Transparency or 0), pr.CanCollide == false and "0" or "1" }, "|"))
	end
end
for _, b in Mock.terrainBalls do
	print(table.concat({ "T", f(b.c.X), f(b.c.Y), f(b.c.Z), f(b.r), b.air and "1" or "0" }, "|"))
end
for tag, set in Mock.tags do
	for inst in set do
		if inst._props.CFrame and not inst._props.Destroyed then
			local p = inst._props.CFrame.p
			print(table.concat({ "M", tag, f(p.X), f(p.Y), f(p.Z), tostring(inst:GetAttribute("Label") or "") }, "|"))
		end
	end
end
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
    parts.append("local Mock = (function()\n" + open(os.path.join(ROOT, "tests", "mock.luau"), encoding="utf-8").read() + "\nend)()")
    parts.append(EXPORT)
    bundle = os.path.join(ROOT, "tests", ".bundle.luau")
    open(bundle, "w", encoding="utf-8").write("\n".join(parts))
    r = subprocess.run([luau, bundle], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        sys.exit(1)
    return r.stdout.splitlines()


def parse(lines):
    parts, balls, markers = [], [], []
    for ln in lines:
        f = ln.split("|")
        if f[0] == "P":
            v = list(map(float, f[3:22]))
            parts.append({"name": f[1], "shape": f[2], "pos": v[0:3], "size": v[3:6], "m": v[6:15], "col": v[15:18],
                          "alpha": 1 - v[18], "solid": f[22] == "1"})
        elif f[0] == "T":
            balls.append({"c": list(map(float, f[1:4])), "r": float(f[4]), "air": f[5] == "1"})
        elif f[0] == "M":
            markers.append({"tag": f[1], "p": list(map(float, f[2:5])), "label": f[5]})
    return parts, balls, markers


def corners(p):
    (x, y, z), (sx, sy, sz), m = p["pos"], p["size"], p["m"]
    out = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                lx, ly, lz = dx * sx, dy * sy, dz * sz
                out.append((x + m[0] * lx + m[1] * ly + m[2] * lz, y + m[3] * lx + m[4] * ly + m[5] * lz, z + m[6] * lx + m[7] * ly + m[8] * lz))
    return out


def hull(pts):
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


AX = {"x": 0, "y": 1, "z": 2}
ZONE_START, HARD_RADIUS = 1800, 2100  # keep in sync with Config.Zone.StartRadius / Config.Arena.HardRadius
MARK_STYLE = {
    "DeployPoint": ("^", "#ff4fd8", 28), "LootSpot": ("s", "#ffb000", 10), "OxygenStation": ("o", "#3cf0a0", 14),
    "FinalZone": ("*", "#ff3030", 120), "ElectricHazard": ("X", "#80d0ff", 40), "ReactorHazard": ("X", "#ff9a30", 60),
}


def render(parts, balls, markers, h, v, depth, title, path, bounds=None, show_markers=True, labels=False, figsize=12, depth_range=None):
    hi, vi, di = AX[h], AX[v], AX[depth]
    if depth_range:
        d0, d1 = depth_range
        parts = [p for p in parts if d0 <= p["pos"][di] <= d1]
        balls = [b for b in balls if d0 - b["r"] <= b["c"][di] <= d1 + b["r"]]
        markers = [m for m in markers if d0 <= m["p"][di] <= d1]
    fig, ax = plt.subplots(figsize=(figsize, figsize))
    ax.set_facecolor("#05070c")
    fig.patch.set_facecolor("#05070c")

    def inside(pt):
        if not bounds:
            return True
        (x0, x1), (y0, y1) = bounds
        return x0 - 200 <= pt[0] <= x1 + 200 and y0 - 200 <= pt[1] <= y1 + 200

    items = []
    for b in balls:
        if b["air"]:
            continue
        c = b["c"]
        items.append((c[di] + b["r"], "ball", b))
    for p in parts:
        items.append((p["pos"][di] + max(p["size"]) / 2, "part", p))
    sign = -1 if depth == "z" else 1  # looking down -Y for plans; side views look along the depth axis
    items.sort(key=lambda t: t[0] * (1 if depth == "y" else sign))
    for _, kind, it in items:
        if kind == "ball":
            c = it["c"]
            if inside((c[hi], c[vi])):
                ax.add_patch(Circle((c[hi], c[vi]), it["r"], color="#6b5f55", alpha=0.85, lw=0))
        else:
            pts = [(q[hi], q[vi]) for q in corners(it)]
            if not inside(pts[0]):
                continue
            hp = hull(pts)
            if len(hp) >= 3:
                ax.add_patch(Polygon(hp, closed=True, facecolor=tuple(it["col"]), alpha=max(0.15, it["alpha"] * (1 if it["solid"] else 0.6)),
                                     edgecolor=(0, 0, 0, 0.35), lw=0.2))
    if show_markers:
        for mk in markers:
            st = MARK_STYLE.get(mk["tag"])
            if st and inside((mk["p"][hi], mk["p"][vi])):
                ax.scatter([mk["p"][hi]], [mk["p"][vi]], marker=st[0], c=st[1], s=st[2], zorder=5, linewidths=0)
                if labels and mk["tag"] == "FinalZone" and mk["label"]:
                    ax.annotate(mk["label"], (mk["p"][hi], mk["p"][vi]), color="white", fontsize=9, xytext=(6, 6), textcoords="offset points")
    if not bounds:
        for r, col in ((ZONE_START, "#b070ff"), (HARD_RADIUS, "#ff5050")):
            ax.add_patch(Circle((0, 0), r, fill=False, ec=col, lw=1, ls="--"))
        lim = HARD_RADIUS + 100
        ax.set_xlim(-lim, lim)
        ax.set_ylim(-lim, lim)
    else:
        ax.set_xlim(*bounds[0])
        ax.set_ylim(*bounds[1])
    if h == "x" and v == "z":
        ax.invert_yaxis()  # plan view: +Z points down the page (Roblox's -Z is "north")
    ax.set_aspect("equal")
    ax.tick_params(colors="#8899aa", labelsize=8)
    for s in ax.spines.values():
        s.set_color("#334455")
    ax.set_title(title, color="white", fontsize=13)
    ax.set_xlabel(h.upper() + " (studs)", color="#8899aa")
    ax.set_ylabel(v.upper() + " (studs)", color="#8899aa")
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("luau") or "/tmp/luau/luau")
    parts, balls, markers = parse(export(luau))
    os.makedirs(OUT, exist_ok=True)
    arena = [p for p in parts if math.hypot(p["pos"][0], p["pos"][2] - 2600) > 200 or abs(p["pos"][1] - 300) > 120]
    render(arena, balls, markers, "x", "z", "y", "Arena plan (top-down). Purple: storm start radius, red: hard boundary",
           os.path.join(OUT, "arena_plan.png"), labels=True)
    render(arena, balls, markers, "x", "y", "z", "Arena elevation (looking along Z)", os.path.join(OUT, "arena_side.png"), labels=True)
    render(arena, balls, markers, "x", "z", "y", "Space station plan (holo doors in cyan)", os.path.join(OUT, "station_plan.png"), bounds=((-300, 620), (-370, 370)), figsize=12)
    render(arena, balls, markers, "z", "y", "x", "Space station elevation (looking along X): hub stack + habitat ring",
           os.path.join(OUT, "station_side.png"), bounds=((-370, 370), (-300, 300)), figsize=12, depth_range=(-300, 620))
    render(arena, balls, markers, "x", "y", "z", "Exploration ship elevation", os.path.join(OUT, "ship_side.png"),
           bounds=((-180, 440), (-60, 130)), figsize=13, depth_range=(-720, -480))
    render(arena, balls, markers, "x", "z", "y", "Exploration ship plan", os.path.join(OUT, "ship_plan.png"), bounds=((-180, 440), (-720, -480)), figsize=13)
    render(arena, balls, markers, "x", "z", "y", "Asteroid mining field plan", os.path.join(OUT, "asteroids_plan.png"), bounds=((-1450, -300), (-150, 900)),
           labels=True, figsize=11)
    lobby = [p for p in parts if not (math.hypot(p["pos"][0], p["pos"][2] - 2600) > 200 or abs(p["pos"][1] - 300) > 120)]
    render(lobby, [], [], "x", "z", "y", "Lobby staging hall plan", os.path.join(OUT, "lobby_plan.png"), bounds=((-75, 75), (2540, 2660)),
           show_markers=False, figsize=9)


if __name__ == "__main__":
    main()
