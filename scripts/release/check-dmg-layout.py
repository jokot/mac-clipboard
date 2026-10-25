"""Check the icon positions that Finder saved in a DMG's .DS_Store file.

Usage: python3 check-dmg-layout.py <.DS_Store> <name>=<x>,<y> ...
Exits with 1 when a name has no position, or a different position.
"""
import struct
import sys


def position(data, name):
    # A record is the file name (UTF-16BE), the code "Iloc", the type "blob",
    # the length 16, then x and y as 4-byte big-endian integers.
    key = name.encode("utf-16-be") + b"Iloc"
    i = data.find(key)
    if i < 0:
        return None
    j = i + len(key)
    if data[j:j + 4] != b"blob":
        return None
    return struct.unpack(">II", data[j + 8:j + 16])


def main():
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    ok = True
    for arg in sys.argv[2:]:
        name, coords = arg.split("=")
        want = tuple(int(v) for v in coords.split(","))
        got = position(data, name)
        if got != want:
            print(f"{name}: position {got}, expected {want}")
            ok = False
        else:
            print(f"{name}: position {got}")
    sys.exit(0 if ok else 1)


main()
