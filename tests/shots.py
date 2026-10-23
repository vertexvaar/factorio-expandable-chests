"""Takes in-game screenshots with a player and the chest window open (opens a Factorio window briefly).

Usage: python tests/shots.py [out_dir]   (default: previews/shots)
"""
import os
import shutil
import subprocess
import sys
import time

import run

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(run.ROOT, "previews", "shots")


def main():
    run.prepare(True, harness="expandable-chests-shots")
    save = os.path.join(run.ENV, "shots.zip")
    created = run.run(run.DEFAULT_EXE, "--create", save)
    if not os.path.exists(save):
        print(created.stdout[-3000:])
        sys.exit("map creation failed")
    cmd = [run.DEFAULT_EXE, "--config", os.path.join(run.ENV, "config", "config.ini"),
           "--mod-directory", os.path.join(run.ENV, "mods"), "--disable-audio", "--load-game", save]
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    game = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out_dir = os.path.join(run.ENV, "write", "script-output", "ec-shots")
    report = os.path.join(out_dir, "report.txt")
    try:
        for _ in range(240):
            time.sleep(0.5)
            if os.path.exists(report) and "done" in open(report).read():
                break
            if game.poll() is not None:
                break
        time.sleep(1)
    finally:
        game.kill()
    log = os.path.join(run.ENV, "write", "factorio-current.log")
    if os.path.exists(log):
        print("\n".join(l for l in open(log, errors="replace").read().splitlines() if "Error" in l)[-3000:])
    if not os.path.isdir(out_dir):
        sys.exit("no screenshots taken")
    print(open(report).read() if os.path.exists(report) else "no report")
    os.makedirs(OUT, exist_ok=True)
    for name in sorted(os.listdir(out_dir)):
        if name.endswith(".png"):
            shutil.copy(os.path.join(out_dir, name), OUT)
            print(os.path.join(OUT, name))


if __name__ == "__main__":
    main()
