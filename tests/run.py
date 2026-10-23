"""Runs the headless in-game tests.

Creates an isolated Factorio environment (own config, write dir and mod dir)
under tests/.env, creates a map with the test harness mod and runs it through
--benchmark. Prints all ECTEST lines and exits non-zero on failure.

Usage: python tests/run.py [--no-space-age] [path-to-factorio.exe]
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENV = os.path.join(ROOT, "tests", ".env")
DEFAULT_EXE = r"C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
MOD_FILES = ["info.json", "data.lua", "data-final-fixes.lua", "control.lua", "shared.lua", "changelog.txt", "thumbnail.png"]
MOD_DIRS = ["graphics", "locale"]


def prepare(space_age, harness="expandable-chests-test"):
    shutil.rmtree(ENV, ignore_errors=True)
    mods = os.path.join(ENV, "mods")
    target = os.path.join(mods, "expandable-chests")
    os.makedirs(target)
    for f in MOD_FILES:
        if os.path.exists(os.path.join(ROOT, f)):
            shutil.copy(os.path.join(ROOT, f), target)
    for d in MOD_DIRS:
        shutil.copytree(os.path.join(ROOT, d), os.path.join(target, d))
    shutil.copytree(os.path.join(ROOT, "tests", harness), os.path.join(mods, harness))
    names = ["base", "elevated-rails", "quality", "space-age", "expandable-chests", harness]
    with open(os.path.join(mods, "mod-list.json"), "w") as f:
        json.dump({"mods": [{"name": n, "enabled": space_age or n == "base" or n.startswith("expandable")} for n in names]}, f)
    write = os.path.join(ENV, "write")
    os.makedirs(os.path.join(ENV, "config"))
    with open(os.path.join(ENV, "config", "config.ini"), "w") as f:
        f.write("[path]\nread-data=__PATH__executable__/../../data\n")
        f.write("write-data=" + write.replace("\\", "/") + "\n")
    return mods


def run(exe, *args):
    cmd = [exe, "--config", os.path.join(ENV, "config", "config.ini"),
           "--mod-directory", os.path.join(ENV, "mods"), "--disable-audio", *args]
    # Without these, the Steam build restarts itself through Steam when graphics are on.
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", env=env)


def main():
    args = sys.argv[1:]
    space_age = "--no-space-age" not in args
    args = [a for a in args if a != "--no-space-age"]
    exe = args[0] if args else DEFAULT_EXE
    prepare(space_age)
    save = os.path.join(ENV, "test.zip")
    created = run(exe, "--create", save)
    if created.returncode != 0 or not os.path.exists(save):
        print(created.stdout[-4000:], created.stderr[-2000:])
        sys.exit("map creation failed")
    bench = run(exe, "--benchmark", save, "--benchmark-ticks", "450", "--benchmark-runs", "1")
    log_path = os.path.join(ENV, "write", "factorio-current.log")
    log = open(log_path, encoding="utf-8", errors="replace").read() if os.path.exists(log_path) else bench.stdout
    lines = [l for l in log.splitlines() if "ECTEST" in l or "Error" in l]
    if "Error" in bench.stdout:
        lines.append(bench.stdout[bench.stdout.index("Error"):][:3000])
    print("\n".join(lines) if lines else log[-4000:])
    if not any("ECTEST DONE" in l for l in lines) or any("ECTEST FAIL" in l for l in lines):
        sys.exit(1)


if __name__ == "__main__":
    main()
