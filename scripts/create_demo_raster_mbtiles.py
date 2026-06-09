#!/usr/bin/env python3
import math
import sqlite3
import struct
import sys
import zlib
from pathlib import Path


def png_rgba(red: int, green: int, blue: int, alpha: int, size: int = 256) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    row = bytes([red, green, blue, alpha]) * size
    raw_scanlines = b"".join(bytes([0]) + row for _ in range(size))
    return signature + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw_scanlines)) + chunk(b"IEND", b"")


PNG_BLUE = png_rgba(0, 118, 255, 96)
PNG_MAGENTA = png_rgba(210, 42, 180, 112)


def tms_y(z: int, y: int) -> int:
    return (2**z - 1) - y


def write_mbtiles(path: Path, name: str, png: bytes, min_zoom: int, max_zoom: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()

    with sqlite3.connect(path) as conn:
        conn.executescript(
            """
            CREATE TABLE metadata (name TEXT, value TEXT);
            CREATE TABLE tiles (
              zoom_level INTEGER,
              tile_column INTEGER,
              tile_row INTEGER,
              tile_data BLOB
            );
            CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
            """
        )
        metadata = {
            "name": name,
            "type": "overlay",
            "version": "1.0.0",
            "description": f"Synthetic {name} raster overlay for local development",
            "format": "png",
            "bounds": "-180,-85.0511,180,85.0511",
            "center": "0,20,2",
            "minzoom": str(min_zoom),
            "maxzoom": str(max_zoom),
            "attribution": "Synthetic local development overlay",
        }
        conn.executemany("INSERT INTO metadata (name, value) VALUES (?, ?)", metadata.items())

        rows = []
        for z in range(min_zoom, max_zoom + 1):
            extent = min(2**z, 4 if z >= 2 else 2**z)
            start = 0 if z < 2 else math.floor((2**z - extent) / 2)
            for x in range(start, start + extent):
                for y in range(start, start + extent):
                    rows.append((z, x, tms_y(z, y), png))
        conn.executemany(
            "INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)",
            rows,
        )


def main() -> int:
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data/mbtiles")
    write_mbtiles(output_dir / "raster-demo-low.mbtiles", "raster-demo-low", PNG_BLUE, 0, 4)
    write_mbtiles(output_dir / "raster-demo-high.mbtiles", "raster-demo-high", PNG_MAGENTA, 3, 6)
    print(f"Wrote demo raster MBTiles to {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
