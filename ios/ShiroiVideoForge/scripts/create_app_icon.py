#!/usr/bin/env python3
"""Deterministic, opaque app icon; no image libraries or network dependencies."""
from pathlib import Path
import json
import struct
import zlib


def main() -> None:
    root = Path(__file__).resolve().parents[1] / 'Assets.xcassets'
    target = root / 'AppIcon.appiconset'
    target.mkdir(parents=True, exist_ok=True)
    size = 1024
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            pixel = (15 + y * 12 // size, 22 + x * 14 // size, 39 + y * 20 // size)
            if (x - 512) ** 2 + (y - 512) ** 2 < 360 ** 2:
                pixel = (29, 71 + y * 40 // size, 102 + x * 40 // size)
            if 410 <= x <= 695 and abs(y - 512) <= (695 - x) * 0.70:
                pixel = (218, 250, 252)
            raw.extend(pixel)
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    (target / 'AppIcon.png').write_bytes(png)
    info = {'version': 1, 'author': 'xcode'}
    (root / 'Contents.json').write_text(json.dumps({'info': info}, indent=2))
    (target / 'Contents.json').write_text(json.dumps({'images': [
        {'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
    ], 'info': info}, indent=2))
    print('Prepared opaque 1024px iPadOS app icon.')

if __name__ == '__main__':
    main()
