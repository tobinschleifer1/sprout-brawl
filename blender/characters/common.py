"""Shared skeleton layouts. Every character uses R15-compatible bone names plus its own chains.

Legs hang off HumanoidRootNode rather than LowerTorso so a torso lean does not drag the feet;
the names still match R15 for the Roblox port.
"""
import sys, os
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import sbuild as S


def humanoid_bones(hip, waist, chest, headTop, shoulderZ, elbowZ, handZ,
                   kneeZ, ankleZ, armY=0.34, legY=0.24, footX=0.26,
                   armStagger=0.16, legStagger=S.STANCE_FRONT, crown=None, legs=True):
    """The standard fighter skeleton, staggered along +X so the profile reads."""
    B = [("HumanoidRootNode", (0, 0, 0), (0, 0, 0.30), None),
         ("LowerTorso", (0, 0, hip), (0, 0, waist), "HumanoidRootNode"),
         ("UpperTorso", (0, 0, waist), (0, 0, chest), "LowerTorso"),
         ("Head", (0, 0, chest), (0, 0, headTop), "UpperTorso")]
    if crown is not None:
        B.append(("Head_Crown", (0, 0, crown), (0, 0, crown + 0.8), "Head"))
    for s, side in ((1, "Left"), (-1, "Right")):
        ax = S.stance_x(s, armStagger)
        B += [(f"{side}UpperArm", (ax, s * armY, shoulderZ), (ax, s * armY * 1.1, elbowZ), "UpperTorso"),
              (f"{side}LowerArm", (ax, s * armY * 1.1, elbowZ), (ax * 1.35, s * armY * 1.18, handZ), f"{side}UpperArm"),
              (f"{side}Hand", (ax * 1.35, s * armY * 1.18, handZ), (ax * 1.5, s * armY * 1.2, handZ - 0.24), f"{side}LowerArm")]
        if legs:
            lx = S.stance_x(s, legStagger)
            B += [(f"{side}UpperLeg", (lx * 0.5, s * legY, hip - 0.06), (lx, s * legY * 1.08, kneeZ), "HumanoidRootNode"),
                  (f"{side}LowerLeg", (lx, s * legY * 1.08, kneeZ), (lx, s * legY * 1.12, ankleZ), f"{side}UpperLeg"),
                  (f"{side}Foot", (lx, s * legY * 1.12, ankleZ), (lx + footX, s * legY * 1.12, ankleZ - 0.2), f"{side}LowerLeg")]
    return B


def chain_bones(prefix, parent, start, step, count, name="Vine"):
    """A trailing chain: vines, fronds, threads. `step` is (dx, dy, dz) per link."""
    B = []
    x, y, z = start
    p = parent
    for i in range(1, count + 1):
        nx, ny, nz = x + step[0], y + step[1], z + step[2]
        bn = f"{prefix}_{name}{i:02d}"
        B.append((bn, (x, y, z), (nx, ny, nz), p))
        p, x, y, z = bn, nx, ny, nz
    return B


# The game palettes, mirrored from web/src/data/characters/*.js so previews are honest.
PALETTES = {
    "Thornlock": dict(primary="#C8365E", secondary="#3F7D3A", tertiary="#5A3A2E", accent="#F7EBDD", glow="#FF2E7E"),
    "CapnSpore": dict(primary="#E39B2C", secondary="#F3E3C3", tertiary="#22345A", accent="#8C5A2B", glow="#FF8A1F"),
    "Sunbeam":   dict(primary="#F4C531", secondary="#5C3B1E", tertiary="#4E8F3B", accent="#FFF6DC", glow="#FFFBEA"),
    "Kelpin":    dict(primary="#6B8E23", secondary="#1F6F78", tertiary="#D9C9A3", accent="#2B3A2A", glow="#2BE5D6"),
    "Cacto":     dict(primary="#7BA05B", secondary="#E8D9A8", tertiary="#D64C8C", accent="#3E4F2E", glow="#FF3D9A"),
    "Duststorm": dict(primary="#C9A85C", secondary="#8A7350", tertiary="#B8B0A0", accent="#A0522D", glow="#FFD24A"),
    "Mycel":     dict(primary="#EDE6D2", secondary="#9A7FB8", tertiary="#4A3728", accent="#C6B8E0", glow="#C08CFF"),
    "Frostbud":  dict(primary="#A9D8F0", secondary="#FFFFFF", tertiary="#5E9E62", accent="#E9D98A", glow="#3DE0FF"),
}


def export(body, name, height, module_file):
    if name in PALETTES:
        S.set_palette(PALETTES[name])
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(module_file))))
    S.preview(os.path.join(root, "blender", "previews", f"{name.lower()}.png"), height=height)
    out = os.path.join(root, "web", "assets", "characters", f"{name.lower()}.glb")
    S.export_glb(out)
    # A .blend as well, so the character can be opened and looked at in Blender directly.
    blend = os.path.join(root, "blender", "blends", f"{name.lower()}.blend")
    S.save_blend(blend, height=height)
    S.report(body, name)
    print("SBUILD_OUT", out, os.path.getsize(out))
    print("SBUILD_BLEND", blend, os.path.getsize(blend))
