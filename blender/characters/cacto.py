"""Cacto — barrel cactus, heavyweight. Silhouette read: barrel.

The widest, lowest figure on the roster. The ribbed barrel is 60% of him and never squashes
much, because he is the immovable one. Stub legs, short thick arms, a magenta flower crown.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, export

TAU = math.tau
HEIGHT = 5.8
HIP = 1.05
BARREL = 2.35          # centre of the barrel
CROWN = 4.05


def bones():
    B = humanoid_bones(hip=HIP, waist=1.85, chest=3.55, headTop=4.5,
                       shoulderZ=3.05, elbowZ=2.55, handZ=2.10,
                       kneeZ=0.62, ankleZ=0.24, armY=0.95, legY=0.42, footX=0.30,
                       armStagger=0.20, legStagger=0.22, crown=CROWN)
    return B


def build():
    P = []

    # ---- the barrel: one big ribbed mass carrying the whole silhouette
    P.append(S.sphere("barrel", "LowerTorso", "primary", r=1.30, loc=(0, 0, BARREL),
                      scale=(1.05, 1.0, 1.30), segs=18, rings=12))
    # eight vertical ribs, spaced so the profile shows three of them
    for i in range(8):
        a = (i / 8) * TAU
        P.append(S.cube(f"rib{i}", "LowerTorso", "accent", size=(0.16, 0.11, 2.24),
                        loc=(math.cos(a) * 1.30, math.sin(a) * 1.22, BARREL),
                        rot=(0, 0, a), bevel=0.05))
    # spines: three rows, tips carry the accent so a stocked Cacto reads at a glance
    for row, z in enumerate((BARREL - 0.85, BARREL, BARREL + 0.85)):
        n = 10 if row == 1 else 8
        rr = 1.30 * math.sqrt(max(0.15, 1 - ((z - BARREL) / 1.69) ** 2))
        for i in range(n):
            a = (i / n) * TAU + row * 0.31
            P.append(S.cone(f"spine{row}_{i}", "LowerTorso", "secondary", r=0.10, depth=0.52,
                            loc=(math.cos(a) * (rr * 1.02), math.sin(a) * (rr * 0.98), z),
                            rot=(0, math.pi / 2, a), segs=5))

    # ---- flower crown: the only soft thing about him
    P.append(S.cyl("crownStem", "Head", "accent", r1=0.30, r2=0.36, depth=0.42,
                   loc=(0, 0, 3.72), segs=10))
    for i in range(7):
        a = (i / 7) * TAU
        P.append(S.petal(f"crownPetal{i}", "Head_Crown", "tertiary",
                         length=0.52, width=0.42, thickness=0.10, curve=-0.16, profile="rose",
                         loc=(math.cos(a) * 0.22, math.sin(a) * 0.22, CROWN - 0.10),
                         rot=(0, 1.15, a)))
    P.append(S.sphere("crownCentre", "Head_Crown", "glow", r=0.20, loc=(0, 0, CROWN + 0.05),
                      scale=(1, 1, 0.7)))

    # ---- face, low and forward on the barrel so it reads in profile
    P.append(S.sphere("muzzle", "Head", "primary", r=0.44, loc=(1.14, 0, BARREL + 0.72),
                      scale=(0.72, 0.9, 0.78)))
    P += S.eyes("Head", at=(1.28, 0, BARREL + 0.90), spacing=0.34, r=0.20, forward=0.02, pupil=0.5)
    P.append(S.cube("mouth", "Head", "dark", size=(0.10, 0.34, 0.09),
                    loc=(1.46, 0, BARREL + 0.50), rot=(0, 0.3, 0), bevel=0.02))

    # ---- arms: short, thick, always slightly raised
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.20)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "primary", r=0.30, length=0.42,
                           loc=(ax, s * 1.02, 2.86), rot=(0.34 * -s, 0, 0), taper=0.9))
        P.append(S.capsule(f"{side}armLow", f"{side}LowerArm", "primary", r=0.26, length=0.36,
                           loc=(ax * 1.3, s * 1.16, 2.36), taper=0.92))
        P.append(S.sphere(f"{side}fist", f"{side}Hand", "primary", r=0.32,
                          loc=(ax * 1.5, s * 1.20, 2.02), scale=(1.05, 0.95, 1)))
        for c in range(3):
            ca = (c / 3) * TAU + 0.5
            P.append(S.cone(f"{side}knuckle{c}", f"{side}Hand", "secondary", r=0.07, depth=0.26,
                            loc=(ax * 1.5 + math.cos(ca) * 0.20, s * 1.20 + math.sin(ca) * 0.10, 2.10),
                            rot=(0, 1.0, ca), segs=5))

    # ---- stub legs and wide flat feet: he is planted
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s, 0.22)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "accent", r=0.30, length=0.30,
                           loc=(lx * 0.7, s * 0.44, 0.86), taper=0.92))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "dark", r=0.27, length=0.24,
                           loc=(lx, s * 0.46, 0.46), taper=0.95))
        P.append(S.cube(f"{side}foot", f"{side}Foot", "dark", size=(0.86, 0.56, 0.32),
                        loc=(lx + 0.15, s * 0.46, 0.17), bevel=0.09))

    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="CactoRig")
    body = S.bind(build(), arm, mesh_name="Cacto")
    export(body, "Cacto", HEIGHT, __file__)


main()
