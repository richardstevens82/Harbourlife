#!/usr/bin/env python3
"""Headless test runner: bundles every game module source + the Roblox API mock + the specs into
one Luau file and runs it with the `luau` CLI.

Usage:  python3 tests/run.py [path-to-luau]     (default: `luau` on PATH, then /tmp/luau/luau)
Exit code is non-zero if any spec fails.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, "tests")


def long_string(s):
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{s}]{eq}]"


sources = {}
for base, _, files in os.walk(os.path.join(ROOT, "src")):
    for f in files:
        if f.endswith(".luau"):
            p = os.path.join(base, f)
            sources[os.path.relpath(p, ROOT).replace(os.sep, "/")] = open(p, encoding="utf-8").read()

parts = ["SOURCES = {"]
for k in sorted(sources):
    parts.append(f'["{k}"] = {long_string(sources[k])},')
parts.append("}")
parts.append("local Mock = (function()\n" + open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read() + "\nend)()")
parts.append(open(os.path.join(HERE, "specs.luau"), encoding="utf-8").read())
bundle = os.path.join(HERE, ".bundle.luau")
open(bundle, "w", encoding="utf-8").write("\n".join(parts))

luau = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("luau") or "/tmp/luau/luau")
r = subprocess.run([luau, bundle])
sys.exit(r.returncode)
