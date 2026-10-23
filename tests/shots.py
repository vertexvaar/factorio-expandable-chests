"""Takes in-game screenshots with a player and the chest window open (opens a Factorio window briefly).

Usage: python tests/shots.py [out_dir] [--locale=en]   (default: previews/shots)
"""
import os
import shutil
import subprocess
import sys
import time

import run


def play(harness, output, timeout=180, locale=None):
    """Loads a fresh map with a player and the given harness mod in a game window until the harness writes
    "DONE" (or "done") to script-output/<output>/report.txt. Returns the output directory."""
    run.prepare(True, harness=harness)
    if locale:
        with open(os.path.join(run.ENV, "config", "config.ini"), "a") as f:
            f.write("[general]\nlocale=" + locale + "\n")
    save = os.path.join(run.ENV, "game.zip")
    created = run.run(run.DEFAULT_EXE, "--create", save)
    if not os.path.exists(save):
        print(created.stdout[-3000:])
        sys.exit("map creation failed")
    cmd = [run.DEFAULT_EXE, "--config", os.path.join(run.ENV, "config", "config.ini"),
           "--mod-directory", os.path.join(run.ENV, "mods"), "--disable-audio", "--load-game", save]
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    game = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out_dir = os.path.join(run.ENV, "write", "script-output", output)
    report = os.path.join(out_dir, "report.txt")
    try:
        for _ in range(timeout * 2):
            time.sleep(0.5)
            if os.path.exists(report) and "done" in open(report).read().lower():
                break
            if game.poll() is not None:
                break
        time.sleep(1)
    finally:
        game.kill()
        game.wait(timeout=30)
    log = os.path.join(run.ENV, "write", "factorio-current.log")
    if os.path.exists(log):
        errors = [l for l in open(log, errors="replace").read().splitlines() if "Error" in l]
        if errors:
            print("\n".join(errors)[-3000:])
    return out_dir


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--locale=")]
    locales = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--locale=")]
    out = args[0] if args else os.path.join(run.ROOT, "previews", "shots")
    out_dir = play("expandable-chests-shots", "ec-shots", locale=locales[0] if locales else None)
    if not os.path.isdir(out_dir):
        sys.exit("no screenshots taken")
    report = os.path.join(out_dir, "report.txt")
    print(open(report).read() if os.path.exists(report) else "no report")
    os.makedirs(out, exist_ok=True)
    for name in sorted(os.listdir(out_dir)):
        if name.endswith(".png"):
            shutil.copy(os.path.join(out_dir, name), out)
            print(os.path.join(out, name))


if __name__ == "__main__":
    main()
