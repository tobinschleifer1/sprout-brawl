"""Thornlock — bramble rose, zoner. Silhouette read: hooded whip.

Proportion budget for a 5.0-stud figure:
    0.00–0.25  feet      0.25–1.75  legs (30%)
    1.75–3.15  torso     3.15–4.90  rose bloom worn as a hood (35%)
Shoulders barely exceed hips; the vines hang past the knee at rest.

The game is side-on, so everything below is shaped for the PROFILE: the torso is deeper
front-to-back than it is wide, the limbs are staggered along the facing axis so both read,
and the vines hang in front of the legs rather than behind them.
"""
import math, sys, os

sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S

TAU = math.tau
HEIGHT = 5.0
HIP = 1.75
CHEST = 3.05
BLOOM = 3.58          # centre of the flower


def bones():
    B = [("HumanoidRootNode", (0, 0, 0), (0, 0, 0.30), None),
         ("LowerTorso", (0, 0, HIP), (0, 0, 2.35), "HumanoidRootNode"),
         ("UpperTorso", (0, 0, 2.35), (0, 0, CHEST), "LowerTorso"),
         ("Head", (0, 0, CHEST), (0, 0, BLOOM + 0.35), "UpperTorso"),
         ("Head_Crown", (0, 0, BLOOM), (0, 0, BLOOM + 0.9), "Head")]
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.16)
        B += [(f"{side}UpperArm", (ax, s * 0.34, 2.92), (ax, s * 0.38, 2.30), "UpperTorso"),
              (f"{side}LowerArm", (ax, s * 0.38, 2.30), (ax * 1.35, s * 0.40, 1.72), f"{side}UpperArm"),
              (f"{side}Hand", (ax * 1.35, s * 0.40, 1.72), (ax * 1.5, s * 0.41, 1.48), f"{side}LowerArm")]
        # vines hang forward of the legs so the profile shows body, then whip
        z, vx, parent = 1.48, ax * 1.5, f"{side}Hand"
        for i in range(1, 5):
            nz, nvx = z - 0.32, ax * 1.5 + 0.13 * i
            B.append((f"{side}Hand_Vine{i:02d}", (vx, s * 0.41, z), (nvx, s * 0.42, nz), parent))
            parent, z, vx = f"{side}Hand_Vine{i:02d}", nz, nvx
        lx = S.stance_x(s)
        B += [(f"{side}UpperLeg", (lx * 0.5, s * 0.24, HIP - 0.06), (lx, s * 0.26, 1.00), "HumanoidRootNode"),
              (f"{side}LowerLeg", (lx, s * 0.26, 1.00), (lx, s * 0.27, 0.30), f"{side}UpperLeg"),
              (f"{side}Foot", (lx, s * 0.27, 0.30), (lx + 0.26, s * 0.27, 0.10), f"{side}LowerLeg")]
    return B


def build():
    P = []

    # ---- torso: one lean vertical, waist narrower than chest by a hair
    P.append(S.capsule("torsoLow", "LowerTorso", "secondary", r=0.34, length=0.48,
                       loc=(0, 0, 2.02), scale=(1.34, 1.0, 1.0), taper=1.14))
    P.append(S.capsule("torsoUp", "UpperTorso", "secondary", r=0.41, length=0.48,
                       loc=(0, 0, 2.66), scale=(1.28, 1.0, 1.0), taper=0.92))
    P.append(S.capsule("neck", "Head", "secondary", r=0.21, length=0.10, loc=(0, 0, 3.06), scale=(1.2, 1, 1)))
    # spine thorns, raked backward so a lash direction reads even on a still frame
    for i in range(5):
        z = 1.92 + i * 0.28
        P.append(S.cone(f"spineThorn{i}", "UpperTorso" if z > 2.35 else "LowerTorso", "tertiary",
                        r=0.082, depth=0.32, loc=(-0.32, 0.0, z), rot=(0, -2.3, 0), segs=6))

    # ---- legs
    for s, side in ((1, "Left"), (-1, "Right")):
        lx = S.stance_x(s)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "secondary", r=0.205, length=0.56,
                           loc=(lx * 0.75, s * 0.25, 1.40), scale=(1.15, 1, 1), taper=0.86))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "dark", r=0.172, length=0.52,
                           loc=(lx, s * 0.26, 0.68), scale=(1.15, 1, 1), taper=0.94))
        P.append(S.cube(f"{side}foot", f"{side}Foot", "tertiary", size=(0.72, 0.38, 0.28),
                        loc=(lx + 0.13, s * 0.27, 0.15), bevel=0.07))

    # ---- arms: thin, long, hands below the hip so the vines start low
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.16)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "secondary", r=0.155, length=0.40,
                           loc=(ax, s * 0.36, 2.62), taper=0.88))
        P.append(S.sphere(f"{side}elbow", f"{side}LowerArm", "secondary", r=0.145,
                          loc=(ax * 1.2, s * 0.39, 2.30)))
        P.append(S.capsule(f"{side}armLow", f"{side}LowerArm", "secondary", r=0.132, length=0.38,
                           loc=(ax * 1.35, s * 0.40, 2.00), taper=0.92))
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "tertiary", r=0.215,
                          loc=(ax * 1.5, s * 0.41, 1.60), scale=(1.05, 0.92, 1.05)))
        # thorn cuff where the vines are anchored
        for c in range(3):
            ca = (c / 3) * TAU + 0.4
            P.append(S.cone(f"{side}cuff{c}", f"{side}Hand", "accent", r=0.045, depth=0.20,
                            loc=(ax * 1.5 + math.cos(ca) * 0.17, s * 0.41 + math.sin(ca) * 0.08, 1.76),
                            rot=(0, 2.6, ca), segs=5))

        # ---- vines: four tapering segments, accent on the business end
        for i in range(1, 5):
            top = 1.48 - (i - 1) * 0.32
            role = "glow" if i == 4 else ("accent" if i == 3 else "tertiary")
            vx = ax * 1.5 + 0.13 * (i - 0.5)
            P.append(S.capsule(f"{side}vine{i}", f"{side}Hand_Vine{i:02d}", role,
                               r=0.092 - (i - 1) * 0.011, length=0.24,
                               loc=(vx, s * 0.41, top - 0.16), rot=(0, 0.38, 0), taper=0.88))
            P.append(S.cone(f"{side}vineThorn{i}", f"{side}Hand_Vine{i:02d}",
                            "glow" if i >= 3 else "accent", r=0.05, depth=0.21,
                            loc=(vx - 0.11, s * 0.41, top - 0.15), rot=(0, -2.5, 0), segs=5))

    # ---- leaf collar across the shoulders: gives her shoulders and completes the hood read
    for i in range(11):
        a = (i / 11) * TAU + 0.2
        back = (1.0 - math.cos(a)) / 2.0
        side = abs(math.sin(a))                       # 1 at the shoulders, 0 front and back
        P.append(S.petal(f"collar{i}", "UpperTorso", "dark",
                         length=(0.58 + 0.24 * back) * (1.0 - 0.30 * side),
                         width=0.52, thickness=0.085, curve=0.30, profile="blade",
                         loc=(math.cos(a) * 0.38, math.sin(a) * 0.38, 2.98),
                         rot=(0, 2.28 - 0.50 * back, a)))
    # ---- leaf skirt at the hip: breaks the leg mass and stops the lower body reading as a tube
    for i in range(7):
        a = (i / 7) * TAU + 0.45
        front = (1.0 + math.cos(a)) / 2.0
        P.append(S.petal(f"skirt{i}", "LowerTorso", "dark",
                         length=0.92 - 0.26 * front, width=0.52, thickness=0.08,
                         curve=0.14, profile="blade",
                         loc=(math.cos(a) * 0.44, math.sin(a) * 0.44, 2.02),
                         rot=(0, 2.92, a)))

    # ---- the bloom. Small core, big overlapping petals; the flower is the head, not a hat on one.
    P.append(S.sphere("headCore", "Head", "primary", r=0.54, loc=(0, 0, BLOOM),
                      scale=(0.98, 1.0, 0.94)))
    # sepal cupping the bloom from beneath, kept clear of the face
    P.append(S.cone("sepal", "Head", "secondary", r=0.36, depth=0.36,
                    loc=(0, 0, BLOOM - 0.42), rot=(math.pi, 0, 0), segs=8))

    def petal_ring(count, radius, z, length, width, tilt, phase, ring, curve, thick):
        parts = []
        for i in range(count):
            a = phase + (i / count) * TAU
            back = (1.0 - math.cos(a)) / 2.0        # 0 across the face, 1 at the back of the hood
            L = length * (0.34 + 0.66 * back)       # front petals shorten so the face stays open
            T = tilt * (1.0 - 0.30 * back)          # back petals stand up into a hood
            parts.append(S.petal(f"petal{ring}_{i}", "Head_Crown", "primary",
                                 length=L, width=width, thickness=thick,
                                 curve=curve, profile="rose",
                                 loc=(math.cos(a) * radius, math.sin(a) * radius, z),
                                 rot=(0, T, a)))
        return parts

    P += petal_ring(14, 0.42, BLOOM - 0.20, 0.70, 0.92, 0.80, 0.00, 0, -0.26, 0.09)
    P += petal_ring(11, 0.30, BLOOM - 0.02, 0.60, 0.80, 0.54, 0.30, 1, -0.24, 0.085)
    P += petal_ring(8, 0.17, BLOOM + 0.16, 0.48, 0.66, 0.28, 0.70, 2, -0.18, 0.08)

    # ---- face: a small muzzle pushed clear of the petals so the profile reads as a head
    P.append(S.sphere("muzzle", "Head", "primary", r=0.30, loc=(0.40, 0, BLOOM - 0.10),
                      scale=(1.05, 0.86, 0.80)))
    P += S.eyes("Head", at=(0.46, 0, BLOOM + 0.04), spacing=0.24, r=0.17, forward=0.02, pupil=0.48)

    return P


def main():
    S.reset_scene()
    parts = build()
    arm = S.build_armature(bones(), name="ThornlockRig")
    body = S.bind(parts, arm, mesh_name="Thornlock")
    S.set_palette(dict(primary="#C8365E", secondary="#3F7D3A", tertiary="#5A3A2E",
                       accent="#F7EBDD", glow="#FF2E7E"))
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    S.preview(os.path.join(root, "blender", "previews", "thornlock.png"), height=HEIGHT)
    out = os.path.join(root, "web", "assets", "characters", "thornlock.glb")
    S.export_glb(out)
    blend = os.path.join(root, "blender", "blends", "thornlock.blend")
    S.save_blend(blend, height=HEIGHT)
    S.report(body, "Thornlock")
    print("SBUILD_OUT", out, os.path.getsize(out))
    print("SBUILD_BLEND", blend, os.path.getsize(blend))


main()
