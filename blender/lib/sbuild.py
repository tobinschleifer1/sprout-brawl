"""
Sprout Brawl — Blender build library.

Every character is a Python script that composes parts, binds each part rigidly to a bone,
joins them into one mesh, and exports .glb for the web build (and .fbx for the Roblox port later).

Conventions
-----------
* 1 Blender unit = 1 Roblox stud. Z is up in Blender; the glTF exporter converts to Y-up.
* Colour is carried by MATERIAL NAME, not by baked pixels, so the web build can swap palettes
  per skin at load time. Legal names are in PALETTE_ROLES.
* Parts are bound rigidly (one bone, weight 1.0). Chunky stylised characters read better with
  rigid parts than with smooth skinning, and it matches how the Roblox R15 rig will behave.
"""

import bpy, bmesh, math, os
from mathutils import Vector, Matrix

TAU = math.pi * 2
PALETTE_ROLES = ["primary", "secondary", "tertiary", "accent", "glow", "dark", "eyeWhite", "eyeDark"]

# Placeholder viewport colours so the .blend is readable if opened by hand.
ROLE_PREVIEW = {
    "primary": (0.78, 0.21, 0.37, 1), "secondary": (0.25, 0.49, 0.23, 1),
    "tertiary": (0.35, 0.23, 0.18, 1), "accent": (0.97, 0.92, 0.87, 1),
    "glow": (1.0, 0.18, 0.49, 1), "dark": (0.13, 0.26, 0.12, 1),
    "eyeWhite": (1, 1, 1, 1), "eyeDark": (0.06, 0.08, 0.06, 1),
}


# --------------------------------------------------------------------------- scene

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0
    sc.render.fps = 60
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


def set_palette(pal):
    """Point the preview materials at this character's real game colours.

    Roles not given are derived the same way the web build derives them, so a Blender preview and
    the running game agree.
    """
    full = dict(pal)
    if "dark" not in full:
        r, g, b, _ = hex_rgba(full["secondary"])
        full["dark"] = None
        ROLE_PREVIEW["dark"] = (r * 0.58, g * 0.58, b * 0.58, 1)
    if "glow" not in full:
        full["glow"] = full["primary"]
    full.setdefault("eyeWhite", "#FFFFFF")
    full.setdefault("eyeDark", "#1B2418")
    for role, hexval in full.items():
        if role not in PALETTE_ROLES or hexval is None:
            continue
        ROLE_PREVIEW[role] = hex_rgba(hexval)
    for role in PALETTE_ROLES:
        m = bpy.data.materials.get(role)
        if m:
            m.diffuse_color = ROLE_PREVIEW[role]
            bsdf = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
            if bsdf:
                bsdf.inputs["Base Color"].default_value = ROLE_PREVIEW[role]


def material(role):
    """Get or make the material for a palette role."""
    assert role in PALETTE_ROLES, f"unknown palette role {role!r}"
    m = bpy.data.materials.get(role)
    if m is None:
        m = bpy.data.materials.new(role)
        m.use_nodes = True
        m.diffuse_color = ROLE_PREVIEW[role]
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = ROLE_PREVIEW[role]
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = 0.85
            for slot in ("Metallic", "Specular IOR Level", "Specular"):
                if slot in bsdf.inputs:
                    bsdf.inputs[slot].default_value = 0.0
    return m


# --------------------------------------------------------------------------- part

class Part:
    """One piece of geometry, bound to one bone."""

    def __init__(self, obj, bone, role):
        self.obj = obj
        self.bone = bone
        self.role = role


def _new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def _finish(ob, role, bone, bevel=0.0, subsurf=0, shade_smooth=False, segments=2):
    ob.data.materials.append(material(role))
    if bevel > 0:
        m = ob.modifiers.new("bev", 'BEVEL')
        m.width = bevel
        m.segments = segments
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(40)
    if subsurf > 0:
        m = ob.modifiers.new("sub", 'SUBSURF')
        m.levels = subsurf
        m.render_levels = subsurf
    if shade_smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    ob["role"] = role
    ob["bone"] = bone
    return Part(ob, bone, role)


def _xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    M = (Matrix.Translation(Vector(loc))
         @ Matrix.Rotation(rot[2], 4, 'Z')
         @ Matrix.Rotation(rot[1], 4, 'Y')
         @ Matrix.Rotation(rot[0], 4, 'X')
         @ Matrix.Diagonal(Vector(scale).to_4d()))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)


# --------------------------------------------------------------------------- primitives

def sphere(name, bone, role, r=1.0, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), segs=14, rings=8, smooth=True, subsurf=0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    _xform(bm, loc, rot, scale)
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth, subsurf=subsurf)


def ico(name, bone, role, r=1.0, subdiv=2, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    _xform(bm, loc, rot, scale)
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth)


def dome(name, bone, role, r=1.0, height=None, loc=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), segs=16, rings=5, smooth=True, skirt=0.0):
    """Upper hemisphere. `skirt` extrudes the rim straight down, which is what makes a mushroom cap
    read as a cap rather than a ball cut in half."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings * 2, radius=r)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                           plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
    rim = [e for e in bm.edges if e.is_boundary]
    if skirt > 0 and rim:
        ret = bmesh.ops.extrude_edge_only(bm, edges=rim)
        verts = [v for v in ret["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, verts=verts, vec=(0, 0, -skirt))
        for v in verts:
            v.co.x *= 0.92
            v.co.y *= 0.92
    rim = [e for e in bm.edges if e.is_boundary]
    if rim:
        bmesh.ops.holes_fill(bm, edges=rim)
    if height is not None:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.z *= height / r
    _xform(bm, loc, rot, scale)
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth)


def cyl(name, bone, role, r1=1.0, r2=None, depth=1.0, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), segs=12, smooth=True, bevel=0.0):
    """Cylinder along local Z, centred at `loc`."""
    r2 = r1 if r2 is None else r2
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r1, radius2=r2, depth=depth)
    _xform(bm, loc, rot, scale)
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth, bevel=bevel)


def cone(name, bone, role, r=0.4, depth=1.0, loc=(0, 0, 0), rot=(0, 0, 0), segs=8, smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=0.0, depth=depth)
    _xform(bm, loc, rot, scale=(1, 1, 1))
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth)


def cube(name, bone, role, size=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.06, subsurf=0, smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    _xform(bm, loc, rot, size)
    return _finish(_new_obj(name, bm), role, bone, bevel=bevel, subsurf=subsurf, shade_smooth=smooth)


def capsule(name, bone, role, r=0.3, length=1.0, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), segs=8, rings=6, taper=1.0):
    """Rounded limb along local Z. `taper` scales the far end (0.6 = tapers to 60%)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co.z += length / 2 if v.co.z > 0 else -length / 2
    if taper != 1.0:
        for v in bm.verts:
            k = (v.co.z + length / 2 + r) / (length + 2 * r)
            f = 1.0 + (taper - 1.0) * k
            v.co.x *= f
            v.co.y *= f
    _xform(bm, loc, rot, scale)
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=True)


# Width profiles sampled evenly from base (k=0) to tip (k=1), as a fraction of `width`.
PROFILE = {
    "rose":   [0.30, 0.74, 0.96, 1.00, 0.90, 0.58, 0.16],   # broad, blunt, overlapping
    "blade":  [0.42, 0.86, 1.00, 0.94, 0.78, 0.50, 0.12],   # leaf / frond
    "spike":  [0.85, 1.00, 0.82, 0.60, 0.40, 0.22, 0.05],   # sunflower ray, tapers hard
    "paddle": [0.34, 0.70, 0.92, 1.00, 1.00, 0.88, 0.30],   # wide all the way, rounded end
    "bell":   [1.00, 0.96, 0.88, 0.80, 0.74, 0.66, 0.40],   # snowdrop tepal, barely tapers
}


def petal(name, bone, role, length=1.0, width=0.35, thickness=0.12, curve=0.35,
          loc=(0, 0, 0), rot=(0, 0, 0), profile="rose", segs=6, smooth=True, twist=0.0):
    """A petal / leaf blade pointing along +Z and curving toward +X.

    Built as a lofted box-section strip rather than a subdivided cube: a stylised petal needs a
    clean profile, not density. ~52 tris each, which keeps a 21-petal rose inside budget.
    `profile` picks the width curve — a rose petal and a sunflower ray are the same code and
    completely different silhouettes.
    """
    prof = PROFILE[profile] if isinstance(profile, str) else profile
    bm = bmesh.new()
    rings = []
    for i in range(segs + 1):
        k = i / segs
        fk = k * (len(prof) - 1)
        i0 = min(int(fk), len(prof) - 2)
        w = width * (prof[i0] + (prof[i0 + 1] - prof[i0]) * (fk - i0))
        w = max(w, width * 0.05)
        t = thickness * (1.0 - 0.45 * k)
        x = curve * k * k
        z = k * length
        tw = twist * k
        ct, st = math.cos(tw), math.sin(tw)
        pts = [(-t / 2, -w / 2), (t / 2, -w / 2), (t / 2, w / 2), (-t / 2, w / 2)]
        rings.append(tuple(bm.verts.new((x + px * ct - py * st, px * st + py * ct, z))
                           for (px, py) in pts))
    for i in range(segs):
        a, b = rings[i], rings[i + 1]
        for j in range(4):
            n = (j + 1) % 4
            bm.faces.new((a[j], a[n], b[n], b[j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bm.normal_update()
    _xform(bm, loc, rot, (1, 1, 1))
    return _finish(_new_obj(name, bm), role, bone, shade_smooth=smooth)


def ribbon(name, bone, role, pts, width=0.5, thickness=0.18, loc=(0, 0, 0), rot=(0, 0, 0), smooth=True):
    """A flat strip through a list of (x, z) points, extruded in Y. Used for kelp and threads."""
    bm = bmesh.new()
    rows = []
    for (x, z) in pts:
        a = bm.verts.new((x - thickness / 2, -width / 2, z))
        b = bm.verts.new((x + thickness / 2, -width / 2, z))
        c = bm.verts.new((x + thickness / 2, width / 2, z))
        d = bm.verts.new((x - thickness / 2, width / 2, z))
        rows.append((a, b, c, d))
    for i in range(len(rows) - 1):
        p, q = rows[i], rows[i + 1]
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((p[j], p[k], q[k], q[j]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    bm.normal_update()
    _xform(bm, loc, rot, (1, 1, 1))
    return _finish(_new_obj(name, bm), role, bone, bevel=0.04, shade_smooth=smooth)


# In a side-on game the near and far limbs must be separated along the facing axis (+X), or the
# profile collapses into one leg and one arm. FRONT is the limb toward the camera-left/forward.
STANCE_FRONT = 0.20
STANCE_BACK = -0.20


def stance_x(side, amount=None):
    """+X offset for a limb. side is 1 (Left, forward) or -1 (Right, back)."""
    a = STANCE_FRONT if amount is None else amount
    return a if side > 0 else -a


def ring_of(count, fn, radius, z=0.0, phase=0.0, tilt=0.0):
    """Place `count` parts evenly around the Z axis. fn(i, angle, loc, rot) -> Part."""
    out = []
    for i in range(count):
        a = phase + (i / count) * TAU
        loc = (math.cos(a) * radius, math.sin(a) * radius, z)
        out.append(fn(i, a, loc, (tilt, 0.0, a)))
    return out


def eyes(bone, at=(0.0, 0.0, 0.0), spacing=0.42, r=0.19, forward=0.0, pupil=0.55, tilt=0.0):
    """A pair of eyes facing +X (the character's forward). Returns the parts."""
    out = []
    for i, s in enumerate((-1, 1)):
        w = sphere(f"eyeW{i}", bone, "eyeWhite", r=r,
                   loc=(at[0] + forward, at[1] + s * spacing, at[2]), scale=(0.75, 1, 1), segs=10, rings=6)
        p = sphere(f"eyeP{i}", bone, "eyeDark", r=r * pupil,
                   loc=(at[0] + forward + r * 0.55, at[1] + s * spacing, at[2] + tilt), segs=8, rings=5)
        out += [w, p]
    return out


# --------------------------------------------------------------------------- armature

def build_armature(bones, name="Rig"):
    """bones: list of (name, head(x,y,z), tail(x,y,z), parent_or_None)."""
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    made = {}
    for (bn, head, tail, parent) in bones:
        eb = arm.edit_bones.new(bn)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.use_connect = False
        made[bn] = eb
    for (bn, head, tail, parent) in bones:
        if parent:
            made[bn].parent = made[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def bind(parts, armature, mesh_name="Body"):
    """Rigidly bind each part to its bone, join everything, add the armature modifier."""
    for p in parts:
        vg = p.obj.vertex_groups.new(name=p.bone)
        vg.add([v.index for v in p.obj.data.vertices], 1.0, 'REPLACE')

    objs = [p.obj for p in parts]
    for ob in objs:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(False)
    # Apply modifiers before joining so bevels/subsurf survive the merge.
    for ob in objs:
        bpy.context.view_layer.objects.active = ob
        for m in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception:
                ob.modifiers.remove(m)

    for ob in objs:
        ob.select_set(True)
    base = objs[0]
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = mesh_name
    body.data.name = mesh_name

    body.parent = armature
    mod = body.modifiers.new("arm", 'ARMATURE')
    mod.object = armature
    mod.use_vertex_groups = True
    return body


def tri_count(ob):
    me = ob.data
    n = 0
    for p in me.polygons:
        n += max(0, len(p.vertices) - 2)
    return n


# --------------------------------------------------------------------------- export

def export_glb(path, extra=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for ob in bpy.context.scene.objects:
        ob.select_set(True)
    kwargs = dict(
        filepath=path, export_format='GLB', use_selection=False,
        export_apply=True, export_yup=True, export_skins=True,
        export_animations=True, export_materials='EXPORT',
        export_normals=True, export_texcoords=True,
        export_cameras=False, export_lights=False,
    )
    if extra:
        kwargs.update(extra)
    while True:
        try:
            bpy.ops.export_scene.gltf(**kwargs)
            return path
        except TypeError as e:
            msg = str(e)
            dropped = None
            for k in list(kwargs):
                if k in msg and k not in ("filepath", "export_format"):
                    dropped = k
                    break
            if dropped is None:
                raise
            kwargs.pop(dropped)


def preview(path, height=5.0, shots=(("side", -1.57), ("three_quarter", -0.85), ("front", 0.0)),
            bg=(0.86, 0.885, 0.845)):
    """Render flat-lit turnaround shots so the model can actually be looked at.

    `shots` are (label, yaw) in radians around the character; the camera distance is derived
    from the model height so the whole figure is always in frame.

    Side view comes first on purpose: Sprout Brawl is played side-on, so the profile is the
    silhouette a player actually reads. A character that only works front-on is not finished.
    """
    import bpy
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = 520, 700
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    # Standard transform keeps the palette true; AgX/Filmic desaturate the whole roster.
    try:
        sc.view_settings.view_transform = 'Standard'
        sc.view_settings.look = 'None'
    except Exception:
        pass

    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55

    lights = []
    def _light(name, kind, energy, size, loc, rot):
        d = bpy.data.lights.new(name, kind)
        d.energy = energy
        if hasattr(d, "size"):
            d.size = size
        ob = bpy.data.objects.new(name, d)
        ob.location = loc
        ob.rotation_euler = rot
        bpy.context.collection.objects.link(ob)
        lights.append(ob)
        return ob

    _light("key", 'AREA', 260, 7, (5.5, -6.0, height * 1.7), (0.85, 0.0, 0.72))
    _light("fill", 'AREA', 90, 9, (-6.0, -3.5, height * 0.9), (1.25, 0.0, -1.05))
    _light("rim", 'AREA', 180, 5, (-3.0, 5.5, height * 1.5), (1.0, 0.0, -2.7))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 70
    cam_data.sensor_fit = 'VERTICAL'
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam

    # distance that fits `height` vertically, with margin
    vfov = 2 * math.atan(cam_data.sensor_height / (2 * cam_data.lens))
    dist = (height * 0.62) / math.tan(vfov / 2)
    aim = Vector((0, 0, height * 0.50))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    made = []
    for label, yaw in shots:
        cam.location = (math.cos(yaw) * dist, math.sin(yaw) * dist, height * 0.62)
        d = aim - Vector(cam.location)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        out = path.replace(".png", f"_{label}.png")
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)
        made.append(out)
    for ob in lights + [cam]:
        bpy.data.objects.remove(ob, do_unlink=True)
    return made


def save_blend(path, height=5.0):
    """Write a .blend so the character can be opened and inspected by hand.

    The headless build never needed one, which is why none existed. This adds a lit camera rig
    and saves the scene, so opening the file shows the finished character rather than an empty
    viewport.
    """
    import bpy
    os.makedirs(os.path.dirname(path), exist_ok=True)

    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", 'AREA'))
    key.data.energy = 260
    key.data.size = 7
    key.location = (5.5, -6.0, height * 1.7)
    key.rotation_euler = (0.85, 0.0, 0.72)
    bpy.context.collection.objects.link(key)

    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", 'AREA'))
    fill.data.energy = 90
    fill.data.size = 9
    fill.location = (-6.0, -3.5, height * 0.9)
    fill.rotation_euler = (1.25, 0.0, -1.05)
    bpy.context.collection.objects.link(fill)

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 70
    cam_data.sensor_fit = 'VERTICAL'
    cam = bpy.data.objects.new("Camera", cam_data)
    vfov = 2 * math.atan(cam_data.sensor_height / (2 * cam_data.lens))
    dist = (height * 0.62) / math.tan(vfov / 2)
    cam.location = (0, -dist, height * 0.62)          # side view: the angle the game is played at
    d = Vector((0, 0, height * 0.5)) - Vector(cam.location)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    if bpy.context.scene.world is None:
        w = bpy.data.worlds.new("World")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.885, 0.845, 1)
        w.node_tree.nodes["Background"].inputs[1].default_value = 0.55
        bpy.context.scene.world = w

    bpy.ops.wm.save_as_mainfile(filepath=path)
    return path


def report(body, name, budget=8000):
    t = tri_count(body)
    flag = "OVER_BUDGET" if t > budget else "ok"
    print(f"SBUILD {name} tris={t} verts={len(body.data.vertices)} budget={budget} {flag} "
          f"materials={[m.name for m in body.data.materials]}")
