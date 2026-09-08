"""Kelpin — kelp frond, grappler. Silhouette read: bulbs on a swaying stipe.

Built from real kelp anatomy rather than a generic green body:
  * holdfast   — a tangled claw that grips, not roots; it anchors and never moves
  * stipe      — the tough flexible stem running the whole height, held in a shallow S
  * pneumatocysts — gas-filled floats along the stipe and one big one for a head; these are
                    the bumps that make the silhouette read as kelp and nothing else
  * blades     — long leaf-like fronds streaming off the floats, trailing behind him

Legless. Everything above the holdfast sways.
"""
import math, sys, os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import chain_bones, export

TAU = math.tau
HEIGHT = 5.6
SEGS = 6
SEG_H = 0.72
BASE = 0.62


def spine_x(i):
    """Shallow S: forward at the waist, back at the shoulders, forward again at the head."""
    return 0.46 * math.sin(i / SEGS * math.pi * 1.7)


def seg_z(i):
    return BASE + i * SEG_H


def bones():
    B = [("HumanoidRootNode", (0, 0, 0), (0, 0, 0.30), None)]
    names = ["LowerTorso", "UpperTorso"] + [f"Spine{i:02d}" for i in range(3, SEGS)] + ["Head"]
    parent = "HumanoidRootNode"
    for i, nm in enumerate(names):
        B.append((nm, (spine_x(i), 0, seg_z(i)), (spine_x(i + 1), 0, seg_z(i + 1)), parent))
        parent = nm
    B.append(("Head_Crown", (spine_x(SEGS), 0, seg_z(SEGS)), (spine_x(SEGS), 0, seg_z(SEGS) + 0.7), "Head"))
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.22)
        z = seg_z(3)
        B += [(f"{side}UpperArm", (ax + spine_x(3), s * 0.40, z), (ax + spine_x(3), s * 0.52, z - 0.58), "UpperTorso"),
              (f"{side}LowerArm", (ax + spine_x(3), s * 0.52, z - 0.58), (ax * 1.4, s * 0.60, z - 1.16), f"{side}UpperArm"),
              (f"{side}Hand", (ax * 1.4, s * 0.60, z - 1.16), (ax * 1.5, s * 0.62, z - 1.46), f"{side}LowerArm")]
        B += chain_bones(f"{side}Hand", f"{side}Hand", (ax * 1.5, s * 0.62, z - 1.46), (0.14, 0, -0.28), 3, name="Vine")
    # blades streaming back off the head float
    B += chain_bones("Crown", "Head_Crown", (spine_x(SEGS) - 0.30, 0, seg_z(SEGS) + 0.30), (-0.34, 0, -0.16), 3, name="Vine")
    return B


def build():
    P = []
    seg_names = ["LowerTorso", "UpperTorso"] + [f"Spine{i:02d}" for i in range(3, SEGS)] + ["Head"]

    # ---- holdfast: a tangled claw, wide and low so he looks planted without having feet
    P.append(S.sphere("holdfast", "HumanoidRootNode", "tertiary", r=0.62, loc=(0.02, 0, 0.34),
                      scale=(1.5, 1.05, 0.62)))
    for i in range(9):
        a = (i / 9) * TAU
        rr = 0.62 + 0.16 * (i % 3)
        P.append(S.capsule(f"haptera{i}", "HumanoidRootNode", "tertiary", r=0.125, length=0.46,
                           loc=(math.cos(a) * rr * 1.35 + 0.02, math.sin(a) * rr * 0.72, 0.20),
                           rot=(0, 1.32, a), taper=0.55, segs=7, rings=4))

    # ---- stipe: a slim flexible stem, the spine everything hangs off
    for i, nm in enumerate(seg_names):
        k = i / SEGS
        r = 0.34 - 0.09 * k
        lean = (spine_x(i + 1) - spine_x(i)) / SEG_H * -1.0
        P.append(S.capsule(f"stipe{i}", nm, "secondary", r=r, length=SEG_H * 0.95,
                           loc=(spine_x(i) + 0.02, 0, seg_z(i) + SEG_H * 0.5),
                           rot=(0, lean, 0), scale=(1.15, 1, 1), taper=0.94))

    # ---- pneumatocysts: the gas floats. These are the mass, and the reason he reads as kelp.
    floats = [(1, 0.36, 0.16), (2, 0.30, -0.10), (3, 0.27, 0.12), (4, 0.26, 0.14)]
    for (i, r, dx) in floats:
        z = seg_z(i) + SEG_H * 0.5
        P.append(S.sphere(f"float{i}", seg_names[i], "primary", r=r,
                          loc=(spine_x(i) + dx, 0, z), scale=(1.15, 0.90, 1.10), segs=11, rings=8))
        # each float carries a blade, exactly as it does on a real frond
        for s_ in (1, -1):
            P.append(S.petal(f"bladeF{i}_{s_}", seg_names[i], "primary",
                             length=1.95 + 0.35 * (i % 2), width=0.66, thickness=0.085,
                             curve=0.72, profile="blade",
                             loc=(spine_x(i) + dx - 0.18, s_ * 0.20, z - 0.04),
                             rot=(0, 2.35 + 0.14 * i, s_ * 0.42), twist=0.7 * s_))

    # ---- head: one big bull-kelp float with blades streaming back off it
    top = seg_z(SEGS)
    P.append(S.sphere("headFloat", "Head", "primary", r=0.56, loc=(spine_x(SEGS) + 0.06, 0, top + 0.26),
                      scale=(1.16, 0.92, 1.04), segs=14, rings=9))
    P += S.eyes("Head", at=(spine_x(SEGS) + 0.50, 0, top + 0.36), spacing=0.26, r=0.155, forward=0.02, pupil=0.48)
    P.append(S.cube("mouth", "Head", "dark", size=(0.10, 0.30, 0.08),
                    loc=(spine_x(SEGS) + 0.60, 0, top + 0.06), rot=(0, 0.25, 0), bevel=0.02))
    for i in range(1, 4):
        for s_ in (1, -1):
            P.append(S.petal(f"crownBlade{i}_{s_}", f"Crown_Vine{i:02d}", "primary",
                             length=1.70, width=0.46, thickness=0.08, curve=0.66, profile="blade",
                             loc=(spine_x(SEGS) - 0.24 - 0.34 * (i - 0.5), s_ * (0.12 + 0.09 * i),
                                  top + 0.30 - 0.14 * (i - 0.5)),
                             rot=(0, 2.10, s_ * (0.26 + 0.12 * i)), twist=0.8 * s_))

    # ---- arms: a small float at the shoulder, then a long grabbing blade
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.22)
        z = seg_z(3)
        P.append(S.sphere(f"{side}shoulderFloat", f"{side}UpperArm", "primary", r=0.25,
                          loc=(ax + spine_x(3), s * 0.42, z - 0.04), scale=(1.1, 0.95, 1)))
        P.append(S.petal(f"{side}bladeUp", f"{side}UpperArm", "primary", length=1.05, width=0.50,
                         thickness=0.12, curve=0.30, profile="blade",
                         loc=(ax + spine_x(3), s * 0.48, z - 0.10), rot=(0, 3.02, s * 0.18)))
        P.append(S.petal(f"{side}bladeLow", f"{side}LowerArm", "primary", length=1.00, width=0.48,
                         thickness=0.11, curve=0.32, profile="blade",
                         loc=(ax * 1.25, s * 0.56, z - 0.66), rot=(0, 3.02, s * 0.22)))
        # the cyan inner edge: this is the part that grabs
        P.append(S.cube(f"{side}edge", f"{side}LowerArm", "glow", size=(0.10, 0.10, 0.78),
                        loc=(ax * 1.5, s * 0.72, z - 0.72), rot=(0, 0.18, 0), bevel=0.02))
        P.append(S.sphere(f"{side}grip", f"{side}Hand", "secondary", r=0.26,
                          loc=(ax * 1.5, s * 0.62, z - 1.40), scale=(1.1, 0.85, 1)))
        for i in range(1, 4):
            P.append(S.capsule(f"{side}tendril{i}", f"{side}Hand_Vine{i:02d}",
                               "glow" if i == 3 else "secondary", r=0.085 - i * 0.009, length=0.20,
                               loc=(ax * 1.5 + 0.14 * (i - 0.5), s * 0.62, z - 1.46 - 0.28 * (i - 0.5)),
                               rot=(0, 0.42, 0), taper=0.85, segs=7, rings=5))
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="KelpinRig")
    body = S.bind(build(), arm, mesh_name="Kelpin")
    export(body, "Kelpin", HEIGHT, __file__)


main()
