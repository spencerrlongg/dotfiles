#!/usr/bin/env python3
"""Draws the fastfetch logo: a pixel-art Great Wave in the Kanagawa Dragon
palette, printed with half blocks (two pixels per cell, one above the other).

  python3 make-logo.py > great-wave.ans

config.jsonc points fastfetch at great-wave.ans; the size here must match the
logo width/height there (W columns, H // 2 rows).
"""
import math

W, H = 34, 32

def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

DEEP, WAVE2, BLUE, BLUE2 = rgb("#223249"), rgb("#2d4f67"), rgb("#658594"), rgb("#8ba4b0")
WHITE, SNOW, FUJI, SUN = rgb("#c5c9c5"), rgb("#a6a69c"), rgb("#393f4d"), rgb("#c4746e")

px = [[None] * W for _ in range(H)]

def water(depth):
    return [BLUE2, BLUE, BLUE, WAVE2, WAVE2, WAVE2, DEEP][min(6, int(depth))]

# Sun
for y in range(H):
    for x in range(W):
        if math.hypot(x - 29, y - 4) < 3.3:
            px[y][x] = SUN

# Fuji, sitting in the trough under the curl
for y in range(18, 27):
    for x in range(W):
        if abs(x - 25.5) <= (y - 18) + 0.6:
            px[y][x] = SNOW if y < 21 or (y < 22 and x % 2) else FUJI

# The curl: a ring around (cx, cy) running from the back of the wave over the
# top to the lip, tightening as it goes so the lip hooks inward
cx, cy = 14.0, 13.0
for y in range(H):
    for x in range(W):
        dx, dy = x - cx, cy - y
        d = math.hypot(dx, dy)
        ang = math.degrees(math.atan2(dy, dx))
        ang = ang if ang > -90 else ang + 360
        along = (200 - ang) / 205  # 0 at the back, 1 at the lip
        if not 0 <= along <= 1:
            continue
        r_out = 12.0 * (1 - 0.38 * along ** 2)
        r_in = r_out - (6.0 - 3.5 * along)
        if r_in <= d <= r_out:
            px[y][x] = WHITE if r_out - d < 1.2 else water((r_out - d) * 1.1 + 1)

# The face: concave, dropping steeply under the curl and flattening into the trough
x0, y0, x1, y1 = cx - 6.5, cy + 1.0, cx + 9.0, 26.0
for y in range(H):
    for x in range(W):
        if x < x0:
            surface = y0 if x > cx - 12 else y0 + (cx - 12 - x) * 0.9
        elif x <= x1:
            surface = y0 + (y1 - y0) * math.sqrt((x - x0) / (x1 - x0))
        else:
            continue
        if y >= surface:
            px[y][x] = BLUE2 if y - surface < 1 else water((y - surface) * 0.45 + 1)

# Sea
for y in range(26, H):
    for x in range(W):
        surface = 26 + 0.8 * math.sin(x * 0.7)
        if y >= surface:
            px[y][x] = WHITE if y - surface < 1 and x % 3 == 0 else water(y - 26 + 1)

# Foam claws flicking off the lip, and spray
for x, y in [(22, 12), (24, 11), (23, 14), (25, 15), (21, 17), (19, 0), (23, 1), (26, 8)]:
    px[y][x] = WHITE

out = []
for row in range(0, H, 2):
    line = []
    for x in range(W):
        top, bottom = px[row][x], px[row + 1][x]
        if top and bottom:
            line.append(f"\x1b[38;2;{top[0]};{top[1]};{top[2]};48;2;{bottom[0]};{bottom[1]};{bottom[2]}m▀")
        elif top:
            line.append(f"\x1b[0;38;2;{top[0]};{top[1]};{top[2]}m▀")
        elif bottom:
            line.append(f"\x1b[0;38;2;{bottom[0]};{bottom[1]};{bottom[2]}m▄")
        else:
            line.append("\x1b[0m ")
        if top and bottom and x + 1 < W:
            line.append("\x1b[0m")
    out.append("".join(line) + "\x1b[0m")
print("\n".join(out))
