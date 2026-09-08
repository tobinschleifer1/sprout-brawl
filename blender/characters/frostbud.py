"""Frostbud — snowdrop, control. Silhouette read: bell.

Narrow, upright, precise. The most symmetrical figure on the roster; stands with heels together.
A drooping snowdrop bell is worn over the head like a helmet, three tepals hanging past the chin.
Bells, teardrops and crystal facets: straight edges where the rest of the cast has curves.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, export

TAU = math.tau
HEIGHT = 5.0
HIP = 1.72
BELL = 3.80


def bones():
    return humanoid_bones(hip=HIP, waist=2.32, chest=3.05, headTop=4.55,
                          shoulderZ=2.90, elbowZ=2.34, handZ=1.80,
                          kneeZ=0.98, ankleZ=0.28, armY=0.32, legY=0.20, footX=0.26,
                          armStagger=0.15, legStagger=0.14, crown=BELL)


def build():
    P = []

    # ---- body: narrow, faceted, heels together
    P.append(S.cyl("torsoLow", "LowerTorso", "tertiary", r1=0.34, r2=0.39, depth=0.62,
                   loc=(0, 0, 2.02), scale=(1.34, 1, 1), segs=8, smooth=False, bevel=0.05))
    P.append(S.cyl("torsoUp", "UpperTorso", "tertiary", r1=0.39, r2=0.34, depth=0.66,
                   loc=(0, 0, 2.66), scale=(1.30, 1, 1), segs=8, smooth=False, bevel=0.05))
    P.append(S.capsule("neck", "Head", "tertiary", r=0.15, length=0.22, loc=(0, 0, 3.14), scale=(1.15, 1, 1)))
    # frost collar: six crystal facets, the visual anchor for Chill
    for i in range(6):
        a = (i / 6) * TAU
        P.append(S.cone(f"shard{i}", "UpperTorso", "primary", r=0.17, depth=0.50,
                        loc=(math.cos(a) * 0.38, math.sin(a) * 0.32, 2.98),
                        rot=(0, 1.05, a), segs=4))
    P.append(S.cyl("belt", "LowerTorso", "accent", r1=0.40, r2=0.40, depth=0.12,
                   loc=(0, 0, 2.34), scale=(1.30, 1, 1), segs=8, smooth=False))

    # ---- the head under the bell
    P.append(S.sphere("headCore", "Head", "secondary", r=0.38, loc=(0.04, 0, BELL - 0.34),
                      scale=(1.0, 0.95, 0.92)))
    P += S.eyes("Head", at=(0.34, 0, BELL - 0.30), spacing=0.26, r=0.15, forward=0.02, pupil=0.48)

    # ---- the bell: a cap plus three long tepals hanging past the chin
    P.append(S.dome("bellCap", "Head_Crown", "primary", r=0.62, height=0.46, skirt=0.12,
                    loc=(0, 0, BELL + 0.26), segs=14, rings=5))
    P.append(S.cyl("pedicel", "Head_Crown", "tertiary", r1=0.09, r2=0.11, depth=0.34,
                   loc=(-0.06, 0, BELL + 0.60), rot=(0, 0.30, 0), segs=8))
    for i in range(3):
        a = (i / 3) * TAU + math.pi / 3
        P.append(S.petal(f"tepal{i}", "Head_Crown", "secondary",
                         length=1.40, width=0.80, thickness=0.13, curve=0.16, profile="bell",
                         loc=(math.cos(a) * 0.32, math.sin(a) * 0.28, BELL + 0.30),
                         rot=(0, math.pi - 0.20, a)))
        P.append(S.cube(f"tepalTip{i}", "Head_Crown", "glow", size=(0.20, 0.34, 0.10),
                        loc=(math.cos(a) * 0.48, math.sin(a) * 0.42, BELL - 1.00),
                        rot=(0, 0.1, a), bevel=0.02))

    # ---- arms end in ice, which is where every hitbox she has lives
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.15)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "tertiary", r=0.115, length=0.42,
                           loc=(ax, s * 0.33, 2.64), taper=0.9))
        P.append(S.capsule(f"{side}armLow", f"{side}LowerArm", "tertiary", r=0.10, length=0.40,
                           loc=(ax * 1.3, s * 0.37, 2.08), taper=0.9))
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "primary", r=0.185,
                          loc=(ax * 1.5, s * 0.38, 1.74)))
        for c in range(3):
            ca = 0.9 + c * 0.7
            P.append(S.cone(f"{side}icicle{c}", f"{side}Hand", "glow", r=0.065, depth=0.40,
                            loc=(ax * 1.5 + math.cos(ca) * 0.16, s * 0.38, 1.58 - 0.06 * c),
                            rot=(0, math.pi - 0.25 + 0.2 * c, 0), segs=4))

    # ---- legs, close together
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s, 0.14)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "tertiary", r=0.155, length=0.52,
                           loc=(lx * 0.7, s * 0.21, 1.38), scale=(1.15, 1, 1), taper=0.88))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "dark", r=0.135, length=0.48,
                           loc=(lx, s * 0.22, 0.66), scale=(1.15, 1, 1), taper=0.92))
        P.append(S.cube(f"{side}shoe", f"{side}Foot", "dark", size=(0.58, 0.28, 0.24),
                        loc=(lx + 0.11, s * 0.22, 0.13), bevel=0.05))
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="FrostbudRig")
    body = S.bind(build(), arm, mesh_name="Frostbud")
    export(body, "Frostbud", HEIGHT, __file__)


main()
