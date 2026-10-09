#!/usr/bin/env python3
"""Build Harbourlife.rbxlx from src/ (same layout as default.project.json) without needing Rojo.
Usage: python3 tools/build_place.py  ->  build/Harbourlife.rbxlx (open it in Roblox Studio)."""
import os, itertools
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = itertools.count(1)

def item(cls, name, children="", extra=""):
    return (f'<Item class="{cls}" referent="RBX{next(ref)}"><Properties>'
            f'<string name="Name">{escape(name)}</string>{extra}</Properties>{children}</Item>')

def script(path):
    base = os.path.basename(path)
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if base.endswith(suffix):
            name = base[: -len(suffix)]
            break
    src = open(path, encoding="utf-8").read()
    assert "]]>" not in src, path
    return item(cls, name, extra=f'<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>')

def folder_children(d):
    out = []
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        out.append(item("Folder", f, folder_children(p)) if os.path.isdir(p) else script(p))
    return "".join(out)

src = lambda *p: os.path.join(ROOT, "src", *p)
spawn = ('<bool name="Anchored">true</bool>'
         '<CoordinateFrame name="CFrame"><X>0</X><Y>1</Y><Z>20</Z><R00>1</R00><R01>0</R01><R02>0</R02>'
         '<R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>'
         '<Vector3 name="size"><X>6</X><Y>1</Y><Z>6</Z></Vector3>')

body = "".join([
    item("Workspace", "Workspace", item("SpawnLocation", "SpawnLocation", extra=spawn)),
    item("ReplicatedStorage", "ReplicatedStorage", item("Folder", "Shared", folder_children(src("ReplicatedStorage", "Shared")))),
    item("ServerScriptService", "ServerScriptService",
         item("Folder", "Systems", folder_children(src("ServerScriptService", "Systems")))
         + script(src("ServerScriptService", "Main.server.luau"))),
    item("StarterPlayer", "StarterPlayer",
         item("StarterPlayerScripts", "StarterPlayerScripts", folder_children(src("StarterPlayer", "StarterPlayerScripts")))),
])
xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">' + body + "</roblox>")
os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
out = os.path.join(ROOT, "build", "Harbourlife.rbxlx")
open(out, "w", encoding="utf-8").write(xml)
print("wrote", out)
