"""Cap'n Spore — chanterelle mushroom, trap. Silhouette read: wide dome.

Low and broad. The cap is wider than his shoulders by half and tilted like a hat; the body is a
barrel in a heavy coat on stubby legs. No sharp corners anywhere.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, export

TAU = math.tau
HEIGHT = 4.8
HIP = 1.05
CAP = 3.92


def bones():
    return humanoid_bones(hip=HIP, waist=1.75, chest=2.62, headTop=4.50,
                          shoulderZ=2.42, elbowZ=1.98, handZ=1.55,
                          kneeZ=0.62, ankleZ=0.22, armY=0.62, legY=0.34, footX=0.28,
                          armStagger=0.18, legStagger=0.22, crown=CAP)


def build():
    P = []

    # ---- barrel torso inside a heavy coat
    P.append(S.capsule("torso", "LowerTorso", "secondary", r=0.56, length=0.52,
                       loc=(0, 0, 1.60), scale=(1.15, 1, 1), taper=1.05))
    P.append(S.capsule("coat", "LowerTorso", "tertiary", r=0.64, length=0.62,
                       loc=(-0.04, 0, 1.72), scale=(1.16, 1, 1), taper=0.98))
    P.append(S.capsule("chest", "UpperTorso", "tertiary", r=0.60, length=0.40,
                       loc=(-0.02, 0, 2.30), scale=(1.16, 1, 1), taper=0.9))
    # lapels and a belt: the coat needs edges or it reads as a sack
    for s_ in (1, -1):
        P.append(S.petal(f"lapel{s_}", "UpperTorso", "accent", length=0.78, width=0.34,
                         thickness=0.10, curve=0.12, profile="blade",
                         loc=(0.52, s_ * 0.30, 2.44), rot=(0.2 * s_, 2.85, s_ * 0.35)))
    P.append(S.cyl("belt", "LowerTorso", "accent", r1=0.68, r2=0.68, depth=0.18,
                   loc=(0, 0, 1.46), scale=(1.14, 1, 1), segs=14))
    P.append(S.cube("buckle", "LowerTorso", "glow", size=(0.14, 0.26, 0.24),
                    loc=(0.76, 0, 1.46), bevel=0.04))

    # ---- the cap: the dominant mass, tilted, with a deep skirt so it reads as a hat
    P.append(S.dome("cap", "Head_Crown", "primary", r=1.52, height=1.00, skirt=0.26,
                    loc=(-0.10, 0, CAP - 0.26), rot=(0, -0.20, 0), segs=20, rings=6))
    P.append(S.cyl("gills", "Head_Crown", "secondary", r1=1.42, r2=1.00, depth=0.28,
                   loc=(-0.07, 0, CAP - 0.40), rot=(0, -0.20, 0), segs=20))
    # radial gill ribs, visible from below and at the rim
    for i in range(16):
        a = (i / 16) * TAU
        P.append(S.cube(f"gill{i}", "Head_Crown", "accent", size=(0.90, 0.055, 0.10),
                        loc=(math.cos(a) * 0.80 - 0.07, math.sin(a) * 0.80, CAP - 0.50),
                        rot=(0, 0, a), bevel=0.02))
    P.append(S.capsule("stem", "Head", "secondary", r=0.36, length=0.70, loc=(0, 0, 3.02), scale=(1.1, 1, 1)))

    # ---- face tucked under the cap brim
    P.append(S.sphere("muzzle", "Head", "secondary", r=0.42, loc=(0.52, 0, 2.92),
                      scale=(0.92, 0.95, 0.82)))
    P += S.eyes("Head", at=(0.64, 0, 3.04), spacing=0.30, r=0.185, forward=0.02, pupil=0.5)
    P.append(S.cube("mouth", "Head", "dark", size=(0.09, 0.30, 0.08), loc=(0.80, 0, 2.78), bevel=0.02))

    # ---- short thick arms
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.18)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "tertiary", r=0.21, length=0.34,
                           loc=(ax, s * 0.64, 2.24), rot=(0.28 * -s, 0, 0), taper=0.9))
        P.append(S.capsule(f"{side}armLow", f"{side}LowerArm", "tertiary", r=0.185, length=0.32,
                           loc=(ax * 1.3, s * 0.70, 1.80), taper=0.92))
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "secondary", r=0.25,
                          loc=(ax * 1.5, s * 0.73, 1.48), scale=(1.05, 0.95, 1)))

    # ---- stubby legs, feet planted wide
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s, 0.22)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "tertiary", r=0.23, length=0.28,
                           loc=(lx * 0.7, s * 0.36, 0.86), taper=0.92))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "dark", r=0.21, length=0.22,
                           loc=(lx, s * 0.37, 0.46), taper=0.95))
        P.append(S.cube(f"{side}boot", f"{side}Foot", "dark", size=(0.70, 0.44, 0.30),
                        loc=(lx + 0.13, s * 0.37, 0.16), bevel=0.09))
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="CapnSporeRig")
    body = S.bind(build(), arm, mesh_name="CapnSpore")
    export(body, "CapnSpore", HEIGHT, __file__)


main()
