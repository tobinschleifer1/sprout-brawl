"""Weapon select-screen icons, 32x32. Writes one .piskel (editable) and one .png (engine) each."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib'))
from sbpixel import *
from math import pi, cos, sin

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'icons')
os.makedirs(OUT, exist_ok=True)
S = 32
INK = hexrgb('#1B1526')          # one shared outline colour keeps the set cohesive

# ---------------------------------------------------------------- SWORD ----
SWORD_MAP = """
................................
................................
...............44...............
..............1342..............
..............1342..............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
.............134342.............
..........cccccccccccc..........
..........cCCCCCCCCCCc..........
..........cccccccccccc..........
..............gGGg..............
..............gGGg..............
..............gGGg..............
..............gGGg..............
.............cCCCCc.............
.............cCCCCc.............
..............cccc..............
................................
................................
"""

def sword():
    steel = ramp(hexrgb('#9FB0C4'), 4, -0.5, 0.55)
    gold = ramp(hexrgb('#C9A227'), 2, -0.35, 0.3)
    grip = ramp(hexrgb('#6B3F2A'), 2, -0.35, 0.25)
    f = from_map(SWORD_MAP, {'1': steel[0], '2': steel[1], '3': steel[2], '4': steel[3],
                             'c': gold[0], 'C': gold[1], 'g': grip[0], 'G': grip[1]})
    f.outline(INK)
    return f

# --------------------------------------------------------------- SCYTHE ----
def scythe():
    f = Frame(S, S)
    wood = ramp(hexrgb('#6B4A32'), 4, -0.45, 0.35)
    blade = ramp(hexrgb('#C2B2DE'), 4, -0.6, 0.5)
    # A wide crescent across the top of the icon, bolted to the head of a raked shaft. The centre
    # sits well below the canvas so the visible span is a shallow, scythe-like sweep.
    CX, CY, R = 12.0, 26.0, 20.0
    A0, A1 = pi * 0.345, pi * 0.675          # right end at the shaft head, left end at the tip

    for off, c in ((-1, wood[0]), (0, wood[2]), (1, wood[1]), (2, wood[0])):
        f.line(8 + off, 30, 19 + off, 10, c)
    f.disc(8, 30, 1, wood[0])

    f.arc(CX, CY, R,       3.0, A0,        A1,        blade[0])
    f.arc(CX, CY, R + 0.4, 2.0, A0 + 0.03, A1 - 0.06, blade[1])
    f.arc(CX, CY, R - 1.3, 1.0, A0 + 0.01, A1 - 0.03, blade[3])   # cutting edge, concave side
    f.arc(CX, CY, R + 1.6, 1.0, A0 + 0.07, A1 - 0.16, blade[2])   # spine highlight

    f.rect(18, 7, 5, 5, wood[0])                                   # tang
    f.rect(19, 8, 3, 3, wood[3])
    f.outline(INK)
    return f

# ------------------------------------------------------------- BLASTERS ----
# One pistol, muzzle-right: slide on top, barrel forward, grip under the rear. Two of them, the
# second mirrored and pushed back, so the icon reads as "blasters" rather than "a gun".
PISTOL_MAP = """
......................
....dddddddddddd......
...d444444444444d.....
...dDDDDDDDDDDDDd.....
...dDDDDDDDDDDDDddd...
...dDDDDDDDDDDDDDDDdmm
...dDDDDDDDDDDDDDDDdMm
...dDDDDDDDDDDDDDDDdmm
...dDDDDDdddddddddddd.
...dDDDDDd............
...dDDDDd.............
....dDDDd.............
....dDDDd.............
.....ddd..............
......................
"""

def blasters():
    body = ramp(hexrgb('#5E6C84'), 4, -0.55, 0.45)
    glow = hexrgb('#FFC44D')
    one = from_map(PISTOL_MAP, {'d': body[0], 'D': body[1], '4': body[3],
                                'm': with_alpha(glow, 200), 'M': hexrgb('#FFF3D0')})
    one.outline(INK)
    other = one.flip_x()
    for y in range(other.h):
        for x in range(other.w):
            q = other.get(x, y)
            if q[3] and q != INK:
                other.px[y * other.w + x] = shade(q, -0.28)
    f = Frame(S, S)
    f.paste(one, 0, 1)
    f.paste(other, 10, 16)
    return f

# ------------------------------------------------------------- GRIMOIRE ----
def grimoire():
    f = Frame(S, S)
    cov = ramp(hexrgb('#5B47A8'), 5, -0.5, 0.45)
    page = ramp(hexrgb('#F0E7D2'), 3, -0.4, 0.2)
    gem = ramp(hexrgb('#59D9F2'), 4, -0.45, 0.55)
    gold = ramp(hexrgb('#D8B23A'), 3, -0.4, 0.35)

    f.poly([(22, 7), (28, 8), (28, 24), (22, 25)], page[1])          # page block
    f.poly([(22, 7), (27, 8), (27, 10), (22, 9)], page[2])
    for k in range(4):
        f.line(23, 12 + k * 3, 27, 13 + k * 3, page[0])

    f.poly([(4, 9), (25, 6), (26, 24), (5, 27)], cov[2])             # cover, tilted
    f.poly([(4, 9), (25, 6), (25, 8), (4, 11)], cov[4])              # lit top edge
    f.poly([(5, 25), (26, 22), (26, 24), (5, 27)], cov[0])           # shadowed bottom
    f.poly([(3, 9), (5, 9), (6, 27), (4, 27)], cov[0])               # spine
    f.line(4, 10, 5, 26, cov[1])

    f.line(7, 11, 22, 9, gold[1]); f.line(7, 24, 22, 22, gold[0])    # gilt border
    f.line(7, 11, 8, 24, gold[0]); f.line(22, 9, 23, 22, gold[1])

    f.ring(14, 16, 6, 1, with_alpha(gem[2], 130), blend=True)        # rune ring
    for k in range(8):
        a = k * pi / 4 + 0.3
        f.set(int(round(14 + cos(a) * 6)), int(round(16 - sin(a) * 6)), gem[3])
    f.disc(14, 16, 3.4, gem[0]); f.disc(14, 16, 2.4, gem[2]); f.disc(13, 15, 1.2, gem[3])
    f.rect(24, 14, 5, 3, gold[0]); f.rect(25, 14, 3, 2, gold[2])     # clasp
    f.outline(INK)
    return f

BUILD = {'sword': sword, 'scythe': scythe, 'blasters': blasters, 'grimoire': grimoire}

if __name__ == '__main__':
    for name, fn in BUILD.items():
        fr = fn()
        Piskel(f'weapon-icon-{name}', S, S, fps=1).add('icon', [fr]).save(os.path.join(OUT, f'{name}.piskel'))
        Piskel(f'weapon-icon-{name}', S, S, fps=1).add('icon', [fr]).save_sheet(os.path.join(OUT, f'{name}.png'))
        print(f'{name:9} {fr.count_opaque():4} px')
