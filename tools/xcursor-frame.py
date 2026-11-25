#!/usr/bin/env python3
"""Writes the first image of one nominal size from an XCursor file as a PNG.

Usage: xcursor-frame.py XCURSOR SIZE OUTPUT.png
Prints "WIDTH HEIGHT XHOT YHOT". XCursor pixels are premultiplied ARGB; they
are un-premultiplied by truncation, as the frames Denial first imported were.
Standard library only: xcur2png 0.7.1 decodes the 64 and 96 pixel entries of
Bibata 2.0.7 as black where the file holds opaque white.
"""

import struct
import sys
import zlib

IMAGE_CHUNK = 0xFFFD0002


def frame(data, size):
    magic, _, _, count = struct.unpack_from("<4sIII", data, 0)
    if magic != b"Xcur":
        raise SystemExit("not an XCursor file")
    for index in range(count):
        kind, subtype, position = struct.unpack_from("<III", data, 16 + 12 * index)
        if kind == IMAGE_CHUNK and subtype == size:
            header, _, _, _, width, height, xhot, yhot, _ = struct.unpack_from(
                "<9I", data, position
            )
            pixels = struct.unpack_from("<%dI" % (width * height), data, position + header)
            return width, height, xhot, yhot, pixels
    raise SystemExit("no %d pixel image" % size)


def png(width, height, pixels):
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for argb in pixels[y * width:(y + 1) * width]:
            alpha = argb >> 24
            channels = ((argb >> 16) & 255, (argb >> 8) & 255, argb & 255)
            if alpha:
                channels = tuple(min(255, value * 255 // alpha) for value in channels)
            rows.extend(channels + (alpha,))

    def chunk(name, body):
        return (
            struct.pack(">I", len(body))
            + name
            + body
            + struct.pack(">I", zlib.crc32(name + body) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )


def main():
    source, size, output = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    with open(source, "rb") as file:
        width, height, xhot, yhot, pixels = frame(file.read(), size)
    with open(output, "wb") as file:
        file.write(png(width, height, pixels))
    print(width, height, xhot, yhot)


main()
