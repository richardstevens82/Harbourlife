#!/usr/bin/env python3
"""Build ZeroGravity.rbxlx from src/ (same layout as default.project.json) without needing Rojo,
and write sourcemap.json (Rojo sourcemap format) for luau-lsp type checking.

Usage:  python3 tools/build_place.py   ->  build/ZeroGravity.rbxlx   (open it in Roblox Studio)

The place file only carries scripts and a few service properties: the whole environment is
generated at runtime by ServerScriptService.Builders when the server starts.
"""
import itertools
import json
import os
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = itertools.count(1)


def item(cls, name, children="", extra=""):
    return (f'<Item class="{cls}" referent="RBX{next(ref)}"><Properties>'
            f'<string name="Name">{escape(name)}</string>{extra}</Properties>{children}</Item>')


def script_class(base):
    for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if base.endswith(suffix):
            return base[: -len(suffix)], cls
    raise ValueError(base)


def script(path):
    name, cls = script_class(os.path.basename(path))
    src = open(path, encoding="utf-8").read()
    assert "]]>" not in src, path
    return item(cls, name, extra=f'<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>')


def folder_children(d):
    out = []
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        out.append(item("Folder", f, folder_children(p)) if os.path.isdir(p) else script(p))
    return "".join(out)


def src(*p):
    return os.path.join(ROOT, "src", *p)


def prop_bool(name, v):
    return f'<bool name="{name}">{"true" if v else "false"}</bool>'


body = "".join([
    item("Workspace", "Workspace", extra='<float name="Gravity">0</float>' + prop_bool("StreamingEnabled", False)),
    item("Lighting", "Lighting", extra='<token name="Technology">4</token>'),  # 4 = Future
    item("Players", "Players", extra=prop_bool("CharacterAutoLoads", False)),
    item("ReplicatedStorage", "ReplicatedStorage", item("Folder", "Shared", folder_children(src("ReplicatedStorage", "Shared")))),
    item("ServerScriptService", "ServerScriptService",
         item("Folder", "Services", folder_children(src("ServerScriptService", "Services")))
         + item("Folder", "Builders", folder_children(src("ServerScriptService", "Builders")))
         + script(src("ServerScriptService", "Main.server.luau"))),
    item("StarterPlayer", "StarterPlayer",
         item("StarterPlayerScripts", "StarterPlayerScripts", folder_children(src("StarterPlayer", "StarterPlayerScripts")))
         + item("StarterCharacterScripts", "StarterCharacterScripts", folder_children(src("StarterPlayer", "StarterCharacterScripts"))),
         extra=prop_bool("EnableMouseLockOption", False)),
])
xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">' + body + "</roblox>")
os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
out = os.path.join(ROOT, "build", "ZeroGravity.rbxlx")
open(out, "w", encoding="utf-8").write(xml)
print("wrote", out)


# Sourcemap (for luau-lsp: resolves script.Parent / game:GetService paths) ------------------------
def sm_dir(d, name, cls="Folder"):
    children = []
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if os.path.isdir(p):
            children.append(sm_dir(p, f))
        else:
            children.append(sm_file(p))
    return {"name": name, "className": cls, "children": children}


def sm_file(p):
    name, cls = script_class(os.path.basename(p))
    return {"name": name, "className": cls, "filePaths": [os.path.relpath(p, ROOT)]}


sourcemap = {"name": "ZeroGravityLastOrbit", "className": "DataModel", "children": [
    {"name": "ReplicatedStorage", "className": "ReplicatedStorage", "children": [sm_dir(src("ReplicatedStorage", "Shared"), "Shared")]},
    {"name": "ServerScriptService", "className": "ServerScriptService", "children": [
        sm_dir(src("ServerScriptService", "Services"), "Services"),
        sm_dir(src("ServerScriptService", "Builders"), "Builders"),
        sm_file(src("ServerScriptService", "Main.server.luau")),
    ]},
    {"name": "StarterPlayer", "className": "StarterPlayer", "children": [
        sm_dir(src("StarterPlayer", "StarterPlayerScripts"), "StarterPlayerScripts", "StarterPlayerScripts"),
        sm_dir(src("StarterPlayer", "StarterCharacterScripts"), "StarterCharacterScripts", "StarterCharacterScripts")]},
]}
json.dump(sourcemap, open(os.path.join(ROOT, "sourcemap.json"), "w"), indent=1)
print("wrote", os.path.join(ROOT, "sourcemap.json"))
