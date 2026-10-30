"""Screenshots linked and unlinked chest shapes of every chest type (opens a Factorio window briefly).

Usage: python tests/seams.py [out_dir]   (default: previews/seams)
"""
import os
import shutil
import sys

import run
import shots


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(run.ROOT, "previews", "seams")
    out_dir = shots.play("expandable-chests-seams", "ec-seams")
    if not os.path.isdir(out_dir):
        sys.exit("no screenshots taken")
    os.makedirs(out, exist_ok=True)
    for name in sorted(os.listdir(out_dir)):
        if name.endswith(".png"):
            shutil.copy(os.path.join(out_dir, name), out)
            print(os.path.join(out, name))


if __name__ == "__main__":
    main()
