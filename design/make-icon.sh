#!/bin/bash
# Renders the app icon slices in Stickermine/Assets.xcassets/AppIcon.appiconset
# from design/icon-pickaxe.svg (spec section 16). Run it again only when the
# SVG changes, then commit the PNGs: release.yml has no icon step.
#
# - The design SVG is full-bleed (its rounded tile fills the 1024 canvas). Mac
#   icons sit on the 824/1024 grid, like Pullcord's and Key54's: the tile is
#   drawn 824 pt wide, 100 pt in from every edge, on a transparent canvas.
# - qlmanage renders through WebKit, which keeps the SVG's drop shadow
#   (NSImage's SVG support drops it), but it flattens the thumbnail onto an
#   opaque page. So the icon is rendered twice, over white and over black,
#   and the alpha is recovered from the difference (alpha = 1 - (white - black)).
# - sips then scales the 1024 px master to every slice.
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="design/icon-pickaxe.svg"
SET="Stickermine/Assets.xcassets/AppIcon.appiconset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The design SVG's root element becomes a nested 824 x 824 viewport at (100, 100)
# of a 1024 x 1024 one, over a full-canvas backdrop.
fit() {
    echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
    echo "<rect width=\"1024\" height=\"1024\" fill=\"$1\"/>"
    sed '1s/<svg /<svg x="100" y="100" /; 1s/width="1024" height="1024"/width="824" height="824"/' "$SVG"
    echo '</svg>'
}
fit "#FFFFFF" > "$WORK/white.svg"
fit "#000000" > "$WORK/black.svg"
for backdrop in white black; do
    qlmanage -t -s 1024 -o "$WORK" "$WORK/$backdrop.svg" > /dev/null 2>&1
    if [ ! -s "$WORK/$backdrop.svg.png" ]; then
        echo "error: qlmanage didn't render $backdrop.svg" >&2
        exit 1
    fi
done

/usr/bin/python3 -I - "$WORK/white.svg.png" "$WORK/black.svg.png" "$WORK/icon_1024.png" <<'PY'
import struct, sys, zlib

def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and color in (2, 6) and interlace == 0, (path, depth, color, interlace)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            up = prev[x]
            corner = prev[x - channels] if x >= channels else 0
            if kind == 1:
                line[x] = (line[x] + left) & 255
            elif kind == 2:
                line[x] = (line[x] + up) & 255
            elif kind == 3:
                line[x] = (line[x] + ((left + up) >> 1)) & 255
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[x] = (line[x] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 255
        rows.append(line)
        prev = line
    return width, height, channels, rows

def write_png(path, width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        out.write(chunk(b"sRGB", b"\x00"))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))

w, h, cw, white = read_png(sys.argv[1])
w2, h2, cb, black = read_png(sys.argv[2])
assert (w, h) == (w2, h2) == (1024, 1024), (w, h, w2, h2)
rows = []
for y in range(h):
    row = bytearray(w * 4)
    for x in range(w):
        on_white = white[y][x * cw:x * cw + 3]
        on_black = black[y][x * cb:x * cb + 3]
        # Over white a pixel shows a*C + (1 - a)*255, over black a*C.
        alpha = 255 - sum(on_white[i] - on_black[i] for i in range(3)) / 3
        alpha = max(0, min(255, round(alpha)))
        if alpha > 0:
            for i in range(3):
                row[x * 4 + i] = max(0, min(255, round(on_black[i] * 255 / alpha)))
        row[x * 4 + 3] = alpha
    rows.append(row)
write_png(sys.argv[3], w, h, rows)
PY

mkdir -p "$SET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}.png" > /dev/null
    if [ "$double" -eq 1024 ]; then
        cp "$WORK/icon_1024.png" "$SET/icon_${size}x${size}@2x.png"
    else
        sips -z "$double" "$double" "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
    fi
done
ls "$SET"/icon_*.png | while read -r slice; do
    echo "$(basename "$slice") $(sips -g pixelWidth "$slice" | awk '/pixelWidth/ { print $2 }') px"
done
