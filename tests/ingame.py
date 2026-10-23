"""In-game tests with a real player and construction robots (opens a Factorio window for about a minute).

Usage: python tests/ingame.py
"""
import os
import sys

from shots import play


def main():
    out_dir = play("expandable-chests-ingame", "ec-ingame", timeout=240)
    report = os.path.join(out_dir, "report.txt")
    text = open(report).read() if os.path.exists(report) else ""
    print(text or "no report")
    if "ECTEST DONE" not in text or "ECTEST FAIL" in text:
        sys.exit(1)


if __name__ == "__main__":
    main()
