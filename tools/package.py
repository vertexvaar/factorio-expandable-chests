"""Builds the mod zip for the mod portal: dist/<name>_<version>.zip with only the files the game needs.

Usage: python tools/package.py
"""
import json
import os
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FILES = ["info.json", "data.lua", "data-final-fixes.lua", "control.lua", "shared.lua", "changelog.txt",
         "thumbnail.png", "LICENSE"]
DIRS = ["locale"]


def main():
    info = json.load(open(os.path.join(ROOT, "info.json"), encoding="utf-8"))
    base = "%s_%s" % (info["name"], info["version"])
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    path = os.path.join(ROOT, "dist", base + ".zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in FILES:
            z.write(os.path.join(ROOT, f), base + "/" + f)
        for d in DIRS:
            for folder, _, names in os.walk(os.path.join(ROOT, d)):
                for n in names:
                    full = os.path.join(folder, n)
                    z.write(full, base + "/" + os.path.relpath(full, ROOT).replace(os.sep, "/"))
    print(path)


if __name__ == "__main__":
    main()
