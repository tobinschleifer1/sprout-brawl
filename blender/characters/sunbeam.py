"""Sunbeam — sunflower, charge zoner. Silhouette read: lollipop.

Tallest and thinnest. Top-heavy on purpose, so she looks slow before she is slow. The disc faces
forward, so in profile the petal ring reads as a crown above and below the head.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, export

TAU = math.tau
HEIGHT = 6.6
HIP = 2.55
DISC = 5.15           # centre of the flower disc
DISC_X = 0.16


def bones():
    return humanoid_bones(hip=HIP, waist=3.30, chest=4.40, headTop=5.80,
                          shoulderZ=4.10, elbowZ=3.50, handZ=2.94,
                          kneeZ=1.42, ankleZ=0.30, armY=0.30, legY=0.26, footX=0.30,
                          armStagger=0.16, legStagger=0.22, crown=DISC)


def build():
    P = []

    # ---- one long stalk, ribbed so it does not read as a pipe
    P.append(S.capsule("stalkLow", "LowerTorso", "tertiary", r=0.22, length=0.60,
                       loc=(0, 0, 2.92), scale=(1.30, 1, 1), taper=1.05))
    P.append(S.capsule("stalkUp", "UpperTorso", "tertiary", r=0.225, length=0.95,
                       loc=(0, 0, 3.85), scale=(1.28, 1, 1), taper=0.94))
    P.append(S.capsule("neck", "Head", "tertiary", r=0.17, length=0.44, loc=(0, 0, 4.60), scale=(1.2, 1, 1)))
    for i in range(5):
        z = 2.80 + i * 0.42
        P.append(S.cube(f"stalkRib{i}", "UpperTorso" if z > 3.2 else "LowerTorso", "secondary",
                        size=(0.09, 0.09, 0.36), loc=(0.27, 0.0, z), bevel=0.025))

    # ---- the disc, held vertically like a face
    # The disc faces the camera, not the direction she walks: side-on, a forward-facing disc is
    # an invisible edge. Her gaze is carried by the eyes instead.
    P.append(S.cyl("disc", "Head", "secondary", r1=0.74, r2=0.78, depth=0.34,
                   loc=(DISC_X, 0, DISC), rot=(math.pi / 2, 0, 0), segs=18, bevel=0.06))
    P.append(S.cyl("discBack", "Head", "tertiary", r1=0.82, r2=0.66, depth=0.16,
                   loc=(DISC_X, 0.22, DISC), rot=(math.pi / 2, 0, 0), segs=16))
    # seed-head texture: a spiral of small studs, cheap and it stops the disc reading as a plate
    for i in range(18):
        t = i * 2.399
        rr = 0.09 + 0.055 * math.sqrt(i)
        P.append(S.sphere(f"seed{i}", "Head", "tertiary", r=0.078,
                          loc=(DISC_X + math.cos(t) * rr, -0.20, DISC + math.sin(t) * rr),
                          scale=(1, 0.7, 1), segs=7, rings=5))
    # the hot centre: brightens one step per Light segment
    P.append(S.sphere("core", "Head", "glow", r=0.21,
                      loc=(DISC_X, -0.24, DISC), scale=(1, 0.55, 1), segs=12, rings=8))

    # ---- fourteen blunt ray petals around the forward axis: a crown in profile
    for i in range(14):
        a = (i / 14) * TAU
        P.append(S.petal(f"ray{i}", "Head_Crown", "primary",
                         length=1.06, width=0.42, thickness=0.10, curve=0.22, profile="spike",
                         loc=(DISC_X + math.cos(a) * 0.70, -0.06, DISC + math.sin(a) * 0.70),
                         rot=(0, math.pi / 2 - a, 0)))

    # ---- face on the disc
    P += S.eyes("Head", at=(DISC_X + 0.20, -0.26, DISC + 0.16), spacing=0.24, r=0.16, forward=0.02, pupil=0.5)
    P.append(S.cube("mouth", "Head", "dark", size=(0.24, 0.09, 0.09),
                    loc=(DISC_X + 0.16, -0.30, DISC - 0.20), bevel=0.02))

    # ---- broad flat leaf arms that catch light on the upper face
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.16)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "tertiary", r=0.105, length=0.42,
                           loc=(ax, s * 0.30, 3.88), rot=(0.55 * -s, 0, 0), taper=0.9))
        P.append(S.petal(f"{side}leaf", f"{side}LowerArm", "tertiary",
                         length=1.05, width=0.62, thickness=0.10, curve=0.34, profile="paddle",
                         loc=(ax * 1.3, s * 0.52, 3.36), rot=(0, 2.05, s * 1.30)))
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "secondary", r=0.145,
                          loc=(ax * 1.5, s * 0.42, 2.94)))

    # ---- short legs under a long body
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s, 0.22)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "tertiary", r=0.155, length=0.80,
                           loc=(lx * 0.7, s * 0.27, 1.95), scale=(1.15, 1, 1), taper=0.88))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "dark", r=0.135, length=0.70,
                           loc=(lx, s * 0.28, 0.88), scale=(1.15, 1, 1), taper=0.94))
        P.append(S.cube(f"{side}foot", f"{side}Foot", "dark", size=(0.66, 0.34, 0.28),
                        loc=(lx + 0.13, s * 0.28, 0.16), bevel=0.07))
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="SunbeamRig")
    body = S.bind(build(), arm, mesh_name="Sunbeam")
    export(body, "Sunbeam", HEIGHT, __file__)


main()
