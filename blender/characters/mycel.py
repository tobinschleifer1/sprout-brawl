"""Mycel — fungal network, summoner. Silhouette read: a woven cluster.

Built from real fungal anatomy rather than a smooth body with mushrooms glued on:
  * rhizomorphs — long strands of hyphae cemented into cords. Mycel's whole body is a BUNDLE of
                  these, visibly woven, because a network is what it is
  * fruiting bodies — caps sprout wherever the network decides, not only on the head: shoulder,
                      hip and arm as well as the crown
  * hyphae      — loose threads trailing off the bundle and dragging on the ground

Nothing repeats and nothing mirrors. It is a committee, so it looks like one.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, chain_bones, export

TAU = math.tau
HEIGHT = 4.8
HIP = 1.55


def bones():
    B = humanoid_bones(hip=HIP, waist=2.10, chest=2.80, headTop=4.10,
                       shoulderZ=2.68, elbowZ=2.14, handZ=1.66,
                       kneeZ=0.88, ankleZ=0.26, armY=0.34, legY=0.22, footX=0.26,
                       armStagger=0.17, legStagger=0.19, crown=3.30)
    B += chain_bones("Torso", "LowerTorso", (-0.34, 0.24, 1.96), (-0.15, 0.03, -0.44), 3, name="Thread")
    B += chain_bones("TorsoB", "LowerTorso", (-0.38, -0.20, 2.18), (-0.17, -0.02, -0.46), 3, name="Thread")
    return B


def cord_bundle(name, bone, role, z, height, radius, count, r_cord, seed, taper=0.95, lean=0.0):
    """A rhizomorph bundle: cords cemented side by side into one limb or torso section."""
    P = []
    for i in range(count):
        a = (i / count) * TAU + seed
        wob = 0.85 + 0.30 * math.sin(seed * 3.1 + i * 2.2)      # no two cords the same
        rr = radius * (0.82 + 0.30 * math.sin(seed * 1.7 + i * 1.3))
        P.append(S.capsule(f"{name}{i}", bone, role, r=r_cord * wob, length=height,
                           loc=(math.cos(a) * rr * 1.25 + lean, math.sin(a) * rr, z),
                           rot=(math.sin(a) * 0.10, math.cos(a) * 0.12, 0),
                           taper=taper, segs=6, rings=4))
    return P


def build():
    P = []

    # ---- torso: two bundles of cords, not a capsule. The weave IS the character.
    P += cord_bundle("cordLow", "LowerTorso", "primary", 1.86, 0.50, 0.31, 7, 0.125, 0.4, lean=0.03)
    P += cord_bundle("cordUp", "UpperTorso", "primary", 2.44, 0.46, 0.33, 7, 0.130, 1.9, lean=0.05)
    # a few cords cross the bundle diagonally so it reads as woven rather than as a fistful of rods
    for i in range(5):
        z = 1.78 + i * 0.34
        P.append(S.capsule(f"weave{i}", "UpperTorso" if z > 2.20 else "LowerTorso", "accent",
                           r=0.062, length=0.62,
                           loc=(0.06, 0, z), rot=(0, 1.30 + 0.22 * (i % 3), 0.5 * i),
                           taper=0.9, segs=6, rings=4))
    P.append(S.capsule("neck", "Head", "primary", r=0.19, length=0.14, loc=(0.05, 0, 2.86), scale=(1.2, 1, 1)))

    # ---- fruiting bodies. They sprout wherever, not in a tidy row.
    def fruit(tag, bone, r, x, y, z, tilt, stem=0.30):
        out = [S.cyl(f"stem{tag}", bone, "primary", r1=r * 0.16, r2=r * 0.20, depth=stem,
                     loc=(x * 0.7, y * 0.7, z - stem * 0.85), rot=(0, tilt * 0.6, 0), segs=7),
               S.dome(f"cap{tag}", bone, "secondary", r=r, height=r * 0.96, skirt=0.07,
                      loc=(x, y, z), rot=(0, tilt, 0), segs=12, rings=5),
               S.sphere(f"glow{tag}", bone, "glow", r=r * 0.30,
                        loc=(x - tilt * r * 0.4, y, z + r * 0.32), scale=(1, 1, 0.45), segs=9, rings=6)]
        # gill ribs under the cap
        for i in range(3):
            a = (i / 3) * TAU
            out.append(S.cube(f"gill{tag}{i}", bone, "accent", size=(r * 0.95, 0.05, 0.06),
                              loc=(x + math.cos(a) * r * 0.45, y + math.sin(a) * r * 0.45, z - r * 0.16),
                              rot=(0, 0, a), bevel=0.015))
        return out

    P.append(S.sphere("headCore", "Head", "primary", r=0.38, loc=(0.09, 0, 3.00),
                      scale=(1.12, 0.96, 0.94)))
    P += fruit("A", "Head_Crown", 0.58, -0.04, 0.02, 3.70, 0.10, 0.46)     # the big one
    P += fruit("B", "Head_Crown", 0.34, -0.34, 0.34, 3.26, 0.48)
    P += fruit("C", "Head_Crown", 0.24, -0.18, -0.36, 3.16, -0.52)
    P += fruit("D", "UpperTorso", 0.30, -0.16, 0.42, 2.72, 0.62)            # shoulder
    P += fruit("E", "LowerTorso", 0.22, 0.22, -0.36, 1.86, -0.70)           # hip
    P += fruit("F", "LeftLowerArm", 0.19, 0.10, 0.44, 2.04, 0.55, 0.20)     # forearm

    # ---- face, set slightly off centre because nothing here is symmetrical
    P += S.eyes("Head", at=(0.40, 0.03, 3.02), spacing=0.26, r=0.16, forward=0.02, pupil=0.5)
    P.append(S.cube("mouth", "Head", "dark", size=(0.08, 0.22, 0.07), loc=(0.46, 0.02, 2.82), bevel=0.02))

    # ---- arms are cords too, one held higher than the other
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.17)
        lift = 0.09 if s > 0 else -0.05
        P += cord_bundle(f"{side}armUp", f"{side}UpperArm", "primary", 2.44 + lift, 0.44, 0.115, 4, 0.075, 0.9 * s)
        P += cord_bundle(f"{side}armLow", f"{side}LowerArm", "primary", 1.94 + lift, 0.42, 0.105, 4, 0.070, 2.3 * s)
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "accent", r=0.185,
                          loc=(ax * 1.5, s * 0.55, 1.60 + lift), scale=(1.05, 0.9, 1)))
    # nudge the arm bundles out to the staggered arm positions
    for prt in P:
        n = prt.obj.name
        for s, side in ((1, "Left"), (-1, "Right")):
            if n.startswith(f"{side}armUp") or n.startswith(f"{side}armLow"):
                prt.obj.location.x += S.stance_x(s, 0.17) * (1.0 if "Up" in n else 1.3)
                prt.obj.location.y += s * (0.50 if "Up" in n else 0.54)

    # ---- trailing hyphae
    for prefix, ys, x0, z0 in (("Torso", 0.24, -0.34, 1.96), ("TorsoB", -0.20, -0.38, 2.18)):
        for i in range(1, 4):
            P.append(S.capsule(f"{prefix}thread{i}", f"{prefix}_Thread{i:02d}", "accent",
                               r=0.055 - i * 0.007, length=0.30,
                               loc=(x0 - 0.15 * (i - 0.5), ys, z0 - 0.44 * (i - 0.5)),
                               rot=(0, -0.32, 0), taper=0.85, segs=6, rings=4))

    # ---- legs: cords again, one foot turned out
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s, 0.19)
        P += cord_bundle(f"{side}legUp", f"{side}UpperLeg", "primary", 1.24, 0.50, 0.140, 4, 0.095, 1.4 * s)
        P += cord_bundle(f"{side}legLow", f"{side}LowerLeg", "tertiary", 0.60, 0.46, 0.125, 4, 0.090, 3.1 * s)
        P.append(S.cube(f"{side}foot", f"{side}Foot", "tertiary", size=(0.60, 0.32, 0.26),
                        loc=(lx + 0.12, s * 0.24, 0.14), rot=(0, 0, 0.16 if s > 0 else -0.05), bevel=0.06))
    for prt in P:
        n = prt.obj.name
        for s, side in ((1, "Left"), (-1, "Right")):
            if n.startswith(f"{side}legUp") or n.startswith(f"{side}legLow"):
                prt.obj.location.x += S.stance_x(s, 0.19) * (0.7 if "Up" in n else 1.0)
                prt.obj.location.y += s * (0.23 if "Up" in n else 0.24)
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="MycelRig")
    body = S.bind(build(), arm, mesh_name="Mycel")
    export(body, "Mycel", HEIGHT, __file__)


main()
