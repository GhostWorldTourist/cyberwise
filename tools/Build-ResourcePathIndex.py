#!/usr/bin/env python3
"""Build the vendored resource-path index from Ultrapunk's SQLite database.

MAINTAINER TOOL. Users never run this and never need Python - it exists so the
vendored artefact can be rebuilt from source when a new game version lands, and
so nobody has to take the binary on trust.

    py tools/Build-ResourcePathIndex.py <path-to>/cyberpunk2077-resource-paths.db \
        skills/cyberwise-conflicts/data/resource-paths-2.31.cwpx

WHY NOT VENDOR THE .db ITSELF

Two reasons, and the second is the one that decided it:

- 79 MB against 11 MB. The same 751,710 paths, because hierarchical paths share
  enormous prefixes and a database row does not exploit that.
- Reading SQLite needs a SQLite engine. This family's whole position is that
  PowerShell is already on the machine and nothing else should need installing,
  and hand-rolling a b-tree reader to dodge a dependency is a worse trade than
  writing a format that needs no reader at all beyond seek-and-read.

FORMAT (all little-endian; the whole file is raw-deflate compressed)

    magic       "CWPX1"
    u32 count           number of paths
    u32 blockSize       paths per front-coded block (64)
    u32 hashOff/hashLen 12 bytes per entry: i64 hash, u32 ordinal - sorted by hash
    u32 blkOff/blkLen   u32 per block: byte offset of the block within the body
    u32 bodyOff/bodyLen front-coded path text, in path-sorted order

    body, per block of `blockSize` paths:
        first entry:  u16 length, bytes
        later entries: u8 sharedPrefixLen, u16 suffixLen, suffix bytes

Front coding is per block rather than over the whole list so a lookup decodes at
most `blockSize` entries instead of 751,710. That is the entire reason the reader
can be a hundred lines of PowerShell.

Hashes are FNV-1a 64-bit over the UTF-8 path with backslash separators, stored
signed because SQLite has no unsigned 64-bit integer. The reader converts.

Source data: https://github.com/VanStorm/Cyberpunk-Modding - CC BY 4.0,
attribution Ultrapunk. See data/ATTRIBUTION.md; this script is the "what was
changed" that the licence asks you to state.
"""
from __future__ import annotations

import sqlite3
import struct
import sys
import zlib
from pathlib import Path

BLOCK = 64
MAGIC = b"CWPX1"


def build(db_path: Path, out_path: Path) -> None:
    db = sqlite3.connect(str(db_path))
    rows = db.execute("SELECT hash, path FROM paths").fetchall()
    db.close()
    if not rows:
        raise SystemExit("no rows in `paths` - wrong database?")

    # Path order for the body, so front coding sees shared prefixes.
    paths = sorted({p for _, p in rows})
    ordinal = {p: i for i, p in enumerate(paths)}

    body = bytearray()
    starts: list[int] = []
    prev = b""
    for i, p in enumerate(paths):
        b = p.encode("utf-8")
        if i % BLOCK == 0:
            starts.append(len(body))
            body += struct.pack("<H", len(b)) + b
        else:
            n = 0
            limit = min(len(b), len(prev), 255)
            while n < limit and b[n] == prev[n]:
                n += 1
            body += bytes([n]) + struct.pack("<H", len(b) - n) + b[n:]
        prev = b

    # Hash order for the index, so the reader can binary-search fixed records.
    # Duplicate hashes cannot happen (hash is the primary key upstream), but a
    # duplicate PATH can map from two hashes; both entries are kept.
    hashes = bytearray()
    for h, p in sorted(rows):
        hashes += struct.pack("<qI", h, ordinal[p])

    blocks = b"".join(struct.pack("<I", s) for s in starts)

    header_len = len(MAGIC) + 4 * 8
    hash_off = header_len
    blk_off = hash_off + len(hashes)
    body_off = blk_off + len(blocks)

    raw = bytearray()
    raw += MAGIC
    raw += struct.pack("<II", len(rows), BLOCK)
    raw += struct.pack("<II", hash_off, len(hashes))
    raw += struct.pack("<II", blk_off, len(blocks))
    raw += struct.pack("<II", body_off, len(body))
    raw += hashes + blocks + body

    # Raw deflate, not gzip: .NET's DeflateStream reads exactly this, with no
    # header handling in the reader.
    packed = zlib.compress(bytes(raw), 6)[2:-4]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(packed)

    print(f"paths      {len(paths):,}")
    print(f"hash rows  {len(rows):,}")
    print(f"raw        {len(raw):,} bytes")
    print(f"written    {out_path}  ({len(packed):,} bytes)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.strip().splitlines()[0] + "\n\nusage: Build-ResourcePathIndex.py <db> <out.cwpx>")
    build(Path(sys.argv[1]), Path(sys.argv[2]))
