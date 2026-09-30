#!/usr/bin/env python3
"""List what is in a packed avm_badge image, biggest first, and how full the slot is.

    python3 packsizes.py avm_badge.avm [substring ...]

With substrings, only modules whose name contains one of them are listed (the total is
always for the whole image). The main.avm slot is 671,744 bytes (0xA4000).
"""
import struct, sys

SLOT = 671744
data = open(sys.argv[1], "rb").read()
want = sys.argv[2:]

# An avmpack: a 24-byte header, then entries of size(4) flags(4) reserved(4) name\0 ...
off, entries = 24, []
while off < len(data):
    size, _flags, _res = struct.unpack(">III", data[off:off + 12])
    if size == 0:
        break
    name = data[off + 12:data.index(b"\0", off + 12)].decode()
    entries.append((size, name))
    off += size

shown = [(s, n) for s, n in entries if not want or any(w in n for w in want)]
for s, n in sorted(shown, reverse=True)[:25 if not want else None]:
    print(f"{s:9,d}  {n}")
if want:
    print(f"{sum(s for s, _ in shown):9,d}  those modules")
print(f"\nimage {len(data):,} bytes in a {SLOT:,}-byte slot: "
      f"{'FITS, ' + format(SLOT - len(data), ',') + ' free' if len(data) <= SLOT else 'OVER by ' + format(len(data) - SLOT, ',')}")
