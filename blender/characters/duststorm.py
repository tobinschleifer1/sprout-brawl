"""Duststorm — tumbleweed, rushdown. Silhouette read: ball.

The smallest and lightest fighter, built from lines rather than volumes: a tangled sphere of
twigs with real gaps in it, thin wire limbs, permanently leaning into the direction of travel.
"""
import math, sys, os, random
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S
from common import humanoid_bones, export

TAU = math.tau
HEIGHT = 4.2
BALL = 2.15
HIP = 1.30


def bones():
    return humanoid_bones(hip=HIP, waist=1.85, chest=2.70, headTop=3.40,
                          shoulderZ=2.45, elbowZ=2.05, handZ=1.70,
                          kneeZ=0.78, ankleZ=0.26, armY=0.60, legY=0.26, footX=0.24,
                          armStagger=0.18, legStagger=0.20, crown=BALL)


def build():
    P = []
    rnd = random.Random(7)          # fixed seed: the tangle must be the same every build

    # ---- the tangle. Twigs, not a shell, so light passes through and the shape stays airy.
    for i in range(26):
        a = rnd.uniform(0, TAU)
        b = rnd.uniform(-1.1, 1.1)
        length = rnd.uniform(1.5, 2.5)
        r = rnd.uniform(0.045, 0.075)
        role = "primary" if i % 3 else "secondary"
        P.append(S.capsule(f"twig{i}", "LowerTorso", role, r=r, length=length, segs=6, rings=4,
                           loc=(math.cos(a) * rnd.uniform(0, 0.35),
                                math.sin(a) * rnd.uniform(0, 0.35),
                                BALL + b * 0.30),
                           rot=(rnd.uniform(0, math.pi), rnd.uniform(0, math.pi), a),
                           taper=0.7))
    # a few outer hoops give the ball a readable outline without filling it in
    for i in range(4):
        a = (i / 4) * math.pi
        for j in range(7):
            t = (j / 7) * TAU
            P.append(S.capsule(f"hoop{i}_{j}", "Head_Crown", "tertiary", r=0.042, length=0.52, segs=6, rings=4,
                               loc=(math.cos(t) * 1.02 * math.cos(a),
                                    math.sin(a) * 1.02 * 0.9,
                                    BALL + math.sin(t) * 1.02),
                               rot=(a, t + math.pi / 2, 0), taper=0.8))
    # accent wires: these are what light up when Momentum is charged
    for j in range(7):
        t = (j / 7) * TAU
        P.append(S.capsule(f"glowwire{j}", "Head_Crown", "glow", r=0.05, length=0.9, segs=6, rings=4,
                           loc=(math.cos(t) * 0.95, 0.18 * math.sin(t * 2), BALL + math.sin(t) * 0.95),
                           rot=(0.4, t + math.pi / 2, 0.2), taper=0.75))

    # ---- face peering out of the tangle
    P.append(S.sphere("faceCore", "Head", "dark", r=0.46, loc=(0.62, 0, BALL + 0.10),
                      scale=(0.8, 1, 0.92)))
    P += S.eyes("Head", at=(0.86, 0, BALL + 0.18), spacing=0.28, r=0.185, forward=0.02, pupil=0.46)

    # ---- wire limbs
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, 0.18)
        P.append(S.capsule(f"{side}armUp", f"{side}UpperArm", "secondary", r=0.065, length=0.36,
                           loc=(ax, s * 0.62, 2.28), rot=(0.5 * -s, 0, 0), taper=0.85))
        P.append(S.capsule(f"{side}armLow", f"{side}LowerArm", "secondary", r=0.055, length=0.32,
                           loc=(ax * 1.35, s * 0.72, 1.90), taper=0.85))
        P.append(S.sphere(f"{side}hand", f"{side}Hand", "accent", r=0.145,
                          loc=(ax * 1.5, s * 0.74, 1.62)))
        lx = S.stance_x(s, 0.20)
        P.append(S.capsule(f"{side}legUp", f"{side}UpperLeg", "secondary", r=0.075, length=0.42,
                           loc=(lx * 0.7, s * 0.27, 1.06), taper=0.85))
        P.append(S.capsule(f"{side}legLow", f"{side}LowerLeg", "tertiary", r=0.062, length=0.36,
                           loc=(lx, s * 0.28, 0.52), taper=0.9))
        P.append(S.cube(f"{side}foot", f"{side}Foot", "tertiary", size=(0.44, 0.24, 0.20),
                        loc=(lx + 0.10, s * 0.28, 0.12), bevel=0.05))
    return P


def main():
    S.reset_scene()
    arm = S.build_armature(bones(), name="DuststormRig")
    body = S.bind(build(), arm, mesh_name="Duststorm")
    export(body, "Duststorm", HEIGHT, __file__)


main()
