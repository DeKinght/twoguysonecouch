"""Buduje model grywalnej postaci (robotnik) w Blenderze i eksportuje do GLB.

Uruchomienie (bez okna):
  blender -b -P tools/blender/build_worker.py -- <wyjście.glb> [folder_podglądów]

Styl: kreskówkowa figurka "z plasteliny" - ciało, ogrodniczki, koszula, wąs itd.
to metaballe (same zlewają się w gładkie bryły), a kask, pas, guziki i podeszwy
to zaokrąglone bryły. Szkielet ma te same nazwy kości co w grze (profil humanoidalny
Godota), wagi liczy Blender automatycznie. Postać stoi w A-pose (ręce opuszczone ~55°), patrzy w +Y
(po eksporcie do glTF: w -Z, jak gracz w Godocie). Wysokość z kaskiem ~1,75 m.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = argv[0] if argv else os.path.join(os.path.dirname(__file__), "worker.glb")
PREVIEW_DIR = argv[1] if len(argv) > 1 else ""

# Promień pola metaballa -> promień widocznej powierzchni (stiffness 2, threshold 0.6).
MB_SURFACE = 0.672

COLORS = {
    "skin": (0.98, 0.72, 0.6),
    "nose": (0.97, 0.6, 0.52),
    "blush": (0.97, 0.64, 0.58),
    "helmet": (0.98, 0.76, 0.16),
    "overalls": (0.27, 0.43, 0.7),
    "overalls_dark": (0.23, 0.38, 0.65),
    "stitch": (0.66, 0.76, 0.9),
    "shirt": (0.86, 0.32, 0.3),
    "moustache": (0.33, 0.21, 0.15),
    "hair": (0.36, 0.22, 0.15),
    "boots": (0.54, 0.32, 0.17),
    "sole": (0.7, 0.48, 0.28),
    "belt": (0.5, 0.32, 0.18),
    "metal": (0.82, 0.82, 0.84),
    "brass": (0.85, 0.66, 0.25),
}


# --- Pomocnicze ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_materials = {}


def srgb_to_linear(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def material(name):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    c = srgb_to_linear(COLORS[name])  # Blender (i glTF) liczą kolory liniowo
    m.diffuse_color = (*c, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*c, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.35 if name in ("helmet", "metal", "brass") else 0.75
    if name in ("metal", "brass"):
        bsdf.inputs["Metallic"].default_value = 0.35  # przy mocnym metallic w grze wychodziły szare
    _materials[name] = m
    return m


def plaid_material():
    """Koszula w czerwono-białą kratę (obrazek generowany tutaj, eksportuje się do GLB)."""
    if "shirt_plaid" in _materials:
        return _materials["shirt_plaid"]
    size = 256
    img = bpy.data.images.new("shirt_plaid", size, size)
    red = COLORS["shirt"]
    light = (0.97, 0.9, 0.88)
    mid = tuple(r * 0.55 + l * 0.45 for r, l in zip(red, light))
    px = []
    for y in range(size):
        for x in range(size):
            bx = (x % 64) < 28
            by = (y % 64) < 28
            c = red if (bx and by) else (mid if (bx or by) else light)
            if x % 64 == 30 or y % 64 == 30:
                c = tuple(v * 0.9 for v in c)
            px.extend((*c, 1.0))
    img.pixels = px
    img.pack()
    m = bpy.data.materials.new("shirt_plaid")
    m.diffuse_color = (*red, 1.0)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nodes.active = tex
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    _materials["shirt_plaid"] = m
    return m


def metaball(name, resolution=0.011):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = 0.6
    obj = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(obj)
    return obj


def mb_ellipsoid(obj, center, semi, rot=(0, 0, 0), stiffness=2.0):
    """Elipsoida o zadanych półosiach POWIERZCHNI (w metrach)."""
    e = obj.data.elements.new(type="ELLIPSOID")
    e.co = Vector(center)
    e.radius = 1.0 / MB_SURFACE
    e.size_x, e.size_y, e.size_z = semi
    e.rotation = Euler(rot).to_quaternion()
    e.stiffness = stiffness
    return e


def mb_ball(obj, center, radius, stiffness=2.0):
    e = obj.data.elements.new(type="BALL")
    e.co = Vector(center)
    e.radius = radius / MB_SURFACE
    e.stiffness = stiffness
    return e


def mb_capsule(obj, a, b, radius, stiffness=2.0):
    """Kapsuła między punktami a i b, o promieniu powierzchni `radius`."""
    a, b = Vector(a), Vector(b)
    d = b - a
    e = obj.data.elements.new(type="CAPSULE")
    e.co = (a + b) / 2
    e.radius = radius / MB_SURFACE
    e.size_x = d.length / 2
    e.rotation = Vector((1, 0, 0)).rotation_difference(d.normalized())
    e.stiffness = stiffness
    return e


def mb_box(obj, center, half, radius=0.04, rot=(0, 0, 0)):
    e = obj.data.elements.new(type="CUBE")
    e.co = Vector(center)
    e.radius = radius / MB_SURFACE
    e.size_x, e.size_y, e.size_z = half
    e.rotation = Euler(rot).to_quaternion()
    return e


def polish(obj, target=4000, voxel=0.006, smooth=6):
    """Jednolita, gładka powierzchnia: przeliczenie siatki na woksele (znikają szwy i
    "kulki" między zlanymi bryłami), wygładzenie i uproszczenie do ~`target` trójkątów."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    mod.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth > 0:
        mod = obj.modifiers.new("smooth", "SMOOTH")
        mod.factor = 0.5
        mod.iterations = smooth
        bpy.ops.object.modifier_apply(modifier=mod.name)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > target:
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def finish_metaball(obj, mat, target=4000, smooth=6, voxel=0.006):
    """Metaball -> siatka -> gładka, jednolita powierzchnia (polish)."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.view_layer.objects.active
    mesh_obj.data.materials.append(mat)
    return polish(mesh_obj, target, voxel, smooth)


def fuse(objs, name, target, voxel=0.005, smooth=4):
    """Skleja kilka brył jednego materiału w JEDNĄ gładką bryłę (np. dłoń z palcami)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    return polish(obj, target, voxel, smooth)


def add_mesh(name, verts_fn, mat, location=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), bevel=0.0, subdiv=0):
    verts_fn()
    obj = bpy.context.active_object
    obj.name = name
    obj.location = location
    obj.scale = scale
    obj.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
        bpy.ops.object.modifier_apply(modifier=m.name)
    if subdiv > 0:
        m = obj.modifiers.new("subdiv", "SUBSURF")
        m.levels = subdiv
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def cut_below(obj, z):
    """Odcina część siatki poniżej wysokości z (np. dół kopuły kasku)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z - obj.location.z), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(obj.data)
    bm.free()


def ellipsoid(name, center, semi, mat, rot=(0, 0, 0), segments=24):
    """Gładka elipsoida jako zwykła siatka (nie zlewa się z sąsiadami - np. osobne palce)."""
    return add_mesh(name, lambda: bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2,
                                                                       radius=1.0),
                    mat, location=center, scale=semi, rot=rot)


def uv_cube(obj, size=0.5):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=size)
    bpy.ops.object.mode_set(mode="OBJECT")


def strap(name, points, width, target, mat, offset=0.012, thickness=0.012):
    """Płaski pasek (szelka) wzdłuż łamanej `points`, przyklejony do powierzchni `target`."""
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(points):
        p = Vector(p)
        a = Vector(points[max(i - 1, 0)])
        b = Vector(points[min(i + 1, len(points) - 1)])
        along = (b - a).normalized()
        side = along.cross(Vector((0, 0, 1))) if abs(along.z) < 0.95 else Vector((1, 0, 0))
        side = Vector((1, 0, 0)) if side.length < 1e-4 else side.normalized()
        if side.x < 0:
            side = -side
        rows.append((bm.verts.new(p - side * width / 2), bm.verts.new(p + side * width / 2)))
    for (a0, a1), (b0, b1) in zip(rows, rows[1:]):
        bm.faces.new((a0, a1, b1, b0))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    sub = obj.modifiers.new("dense", "SUBSURF")
    sub.levels = 3
    sw = obj.modifiers.new("hug", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.offset = offset
    so = obj.modifiers.new("thick", "SOLIDIFY")
    so.thickness = thickness
    so.offset = 0.0
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


# --- Części postaci --------------------------------------------------------------------------

def build_skin():
    o = metaball("Skin")
    # Głowa: czaszka (pod kaskiem) + pucołowata twarz z policzkami i podbródkiem.
    mb_ellipsoid(o, (0, 0.0, 1.34), (0.215, 0.205, 0.2))
    mb_ellipsoid(o, (0, 0.03, 1.16), (0.235, 0.2, 0.15))               # pyzata żuchwa, bez szyi
    mb_ellipsoid(o, (0, 0.09, 1.075), (0.12, 0.1, 0.05))               # podbródek
    for s in (1, -1):
        mb_ellipsoid(o, (s * 0.13, 0.1, 1.2), (0.1, 0.09, 0.09))        # policzki
        mb_ellipsoid(o, (s * 0.228, 0.0, 1.29), (0.035, 0.045, 0.065))  # uszy
    # Ręce budowane w T-pose wzdłuż X (potem opuszczane do A-pose): grube, "misiowate"
    # ramię spod rękawa, masywne przedramię zwężające się do nadgarstka i duża dłoń.
    for s in (1, -1):
        mb_capsule(o, (s * 0.4, 0, 0.945), (s * 0.7, 0, 0.94), 0.074)
        mb_ellipsoid(o, (s * 0.47, 0, 0.945), (0.07, 0.082, 0.082))     # ramię pod rękawem
        mb_ellipsoid(o, (s * 0.6, 0, 0.942), (0.115, 0.09, 0.09))       # mięsień przedramienia
        mb_ellipsoid(o, (s * 0.79, 0.0, 0.935), (0.09, 0.085, 0.055))   # śródręcze (wnętrzem w dół)
    return finish_metaball(o, material("skin"), 10**9, smooth=4, voxel=0.005)


def build_hands():
    """Palce jako osobne bryły (na obrazku wyraźnie rozdzielone), lekko zgięte w dół, kciuk do przodu."""
    skin = material("skin")
    parts = []
    for s in (1, -1):
        for i, y in enumerate((-0.058, -0.02, 0.02, 0.058)):
            reach = 1.0 if i in (1, 2) else 0.85
            # Grube, lekko podkulone palce (jak na referencji).
            parts.append(ellipsoid("Finger", (s * (0.865 + 0.015 * reach), y, 0.928), (0.05 * reach, 0.032, 0.034),
                                   skin, rot=(0, s * 0.3, 0), segments=16))
            parts.append(ellipsoid("FingerTip", (s * (0.905 + 0.02 * reach), y, 0.895), (0.04 * reach, 0.03, 0.032),
                                   skin, rot=(0, s * 1.0, 0), segments=16))
        parts.append(ellipsoid("Thumb", (s * 0.8, 0.085, 0.922), (0.034, 0.056, 0.034), skin,
                               rot=(0, 0, s * -0.4), segments=16))
        parts.append(ellipsoid("ThumbTip", (s * 0.83, 0.128, 0.912), (0.03, 0.038, 0.03), skin,
                               rot=(0, 0, s * -0.6), segments=16))
    return parts


def build_nose_and_blush():
    nose = metaball("Nose")
    mb_ellipsoid(nose, (0, 0.235, 1.3), (0.085, 0.078, 0.078))
    parts = [finish_metaball(nose, material("nose"), 2500, voxel=0.004)]
    for s in (1, -1):
        b = metaball("Blush" + ("R" if s > 0 else "L"))
        mb_ellipsoid(b, (s * 0.13, 0.178, 1.285), (0.06, 0.014, 0.045), rot=(0, 0, s * -0.6))
        parts.append(finish_metaball(b, material("blush"), 400, voxel=0.004))
    return parts


def build_moustache():
    o = metaball("Moustache", 0.009)
    # Dwa pękate "skrzydła" pod nosem, z lekkim wcięciem na środku i końcami w dół.
    mb_ellipsoid(o, (0, 0.248, 1.232), (0.045, 0.038, 0.032))
    for s in (1, -1):
        mb_ellipsoid(o, (s * 0.075, 0.24, 1.228), (0.08, 0.05, 0.045), rot=(0, s * 0.2, s * -0.25))
        mb_ellipsoid(o, (s * 0.15, 0.205, 1.2), (0.055, 0.045, 0.045), rot=(0, s * 0.6, s * -0.55))
    return [finish_metaball(o, material("moustache"), 3500, voxel=0.004)]


def build_hair():
    o = metaball("Hair")
    # Pas włosów pod kaskiem: szeroko z tyłu, wąsko nad uszami, krótkie baki przed uchem.
    mb_ellipsoid(o, (0, -0.07, 1.31), (0.22, 0.142, 0.085))
    for s in (1, -1):
        mb_ellipsoid(o, (s * 0.185, -0.03, 1.35), (0.035, 0.1, 0.038))
        mb_ellipsoid(o, (s * 0.212, 0.0, 1.345), (0.014, 0.035, 0.042))
    return finish_metaball(o, material("hair"), 2500, voxel=0.005)


def build_helmet():
    brim_z = 1.395
    dome = add_mesh("HelmetDome", lambda: bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1),
                    material("helmet"), location=(0, -0.005, brim_z), scale=(0.25, 0.272, 0.295))
    cut_below(dome, brim_z)
    ridge = add_mesh("HelmetRidge", lambda: bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=24, radius=1),
                     material("helmet"), location=(0, -0.005, brim_z), scale=(0.07, 0.284, 0.31))
    cut_below(ridge, brim_z + 0.01)
    # Daszek: wąski wokół głowy, wysunięty do przodu jak czapka - zasłania oczy.
    brim = add_mesh("HelmetBrim", lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1, depth=1),
                    material("helmet"), location=(0, 0.03, brim_z), scale=(0.272, 0.335, 0.042), bevel=0.016)
    return [dome, ridge, brim]


def build_shirt():
    o = metaball("Shirt")
    mb_ellipsoid(o, (0, 0.0, 0.92), (0.3, 0.2, 0.15))
    mb_ellipsoid(o, (0, 0.06, 1.0), (0.16, 0.12, 0.06))                  # wycięcie pod szyją
    for s in (1, -1):
        mb_ball(o, (s * 0.27, 0, 0.95), 0.115)                             # szeroki bark
        mb_capsule(o, (s * 0.3, 0, 0.945), (s * 0.46, 0, 0.945), 0.1)     # krótki, szeroki rękaw do połowy ramienia
    obj = finish_metaball(o, plaid_material(), 9000)
    uv_cube(obj)
    parts = [obj]
    for s in (1, -1):
        # Podwinięty mankiet rękawa.
        # Podwinięty mankiet: pierścień (bez denek - te wyglądały jak lewitujące krążki na barkach).
        cuff = add_mesh("SleeveCuff", lambda: bpy.ops.mesh.primitive_torus_add(
                            major_radius=0.098, minor_radius=0.026, major_segments=40, minor_segments=12),
                        plaid_material(), location=(s * 0.468, 0, 0.945), scale=(1.0, 1.0, 1.25),
                        rot=(0, math.pi / 2, 0))
        uv_cube(cuff, 0.25)
        parts.append(cuff)
        # Szpiczasty kołnierzyk: płaskie trójkąty leżące na piersi, tworzą "V" pod brodą.
        collar = flap("Collar", [(s * 0.012, 0.2, 1.045), (s * 0.135, 0.13, 1.075), (s * 0.075, 0.215, 0.955)],
                      obj, plaid_material())
        uv_cube(collar, 0.25)
        parts.append(collar)
    parts.append(ellipsoid("ShirtButton", (0, 0.212, 0.968), (0.013, 0.007, 0.013), material("brass"), segments=10))
    return parts


def stitches(target, points, spacing=0.019):
    """Przerywany szew (kreseczki) wzdłuż łamanej, położony na powierzchni `target`."""
    pts = [Vector(p) for p in points]
    marks = []
    for a, b in zip(pts, pts[1:]):
        seg = b - a
        n = max(1, int(seg.length / spacing))
        for i in range(n):
            marks.append((a + seg * ((i + 0.5) / n), seg.normalized()))
    out = []
    for p, t in marks:
        ok, loc, normal, _ = target.closest_point_on_mesh(p)
        if not ok:
            continue
        rot = Vector((1, 0, 0)).rotation_difference(t).to_euler()
        out.append(ellipsoid("Stitch", loc + normal * 0.004, (0.0065, 0.0025, 0.0025), material("stitch"),
                             rot=tuple(rot), segments=8))
    return out


def flap(name, tri, target, mat, offset=0.012, thickness=0.014):
    """Płaski wielokąt (róg kołnierzyka, kieszeń) przyklejony do powierzchni `target`."""
    bm = bmesh.new()
    vs = [bm.verts.new(Vector(p)) for p in tri]
    bm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    sub = obj.modifiers.new("dense", "SUBSURF")
    sub.levels = 4
    sub.subdivision_type = "SIMPLE"
    sw = obj.modifiers.new("hug", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.offset = offset
    so = obj.modifiers.new("thick", "SOLIDIFY")
    so.thickness = thickness
    so.offset = 0.0
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build_overalls():
    o = metaball("Overalls")
    mb_ellipsoid(o, (0, 0.06, 0.7), (0.3, 0.27, 0.27))        # wielki brzuch, wystaje do przodu
    mb_ellipsoid(o, (0, -0.07, 0.7), (0.27, 0.17, 0.25))      # płaskie plecy
    mb_ellipsoid(o, (0, -0.02, 0.52), (0.31, 0.25, 0.13))     # biodra
    mb_ellipsoid(o, (0, -0.09, 0.5), (0.26, 0.17, 0.12))      # pupa
    mb_box(o, (0, 0.17, 0.86), (0.17, 0.05, 0.06), 0.03)       # szeroki śliniak
    for s in (1, -1):
        mb_capsule(o, (s * 0.175, 0, 0.47), (s * 0.175, 0, 0.19), 0.115)  # proste nogawki
    obj = finish_metaball(o, material("overalls"), 12000)
    parts = [obj]
    # Duża kieszeń na śliniaku, położona na powierzchni brzucha.
    loc, n = surface_point(obj, 0.78, 0.0)
    # Kieszeń w kształcie tarczy (szpic na dole) z jasnym przeszyciem, jak na referencji.
    outline = [(-0.105, 0.855), (0.105, 0.855), (0.105, 0.72), (0.0, 0.665), (-0.105, 0.72)]
    pocket = flap("Pocket", [(x, 0.35, z) for x, z in outline], obj, material("overalls_dark"),
                  offset=0.008, thickness=0.012)
    parts.append(pocket)
    inner = [(-0.088, 0.84), (0.088, 0.84), (0.088, 0.726), (0.0, 0.682), (-0.088, 0.726), (-0.088, 0.84)]
    parts += stitches(pocket, [(x, 0.4, z) for x, z in inner])
    parts += stitches(pocket, [(-0.088, 0.4, 0.82), (0.088, 0.4, 0.82)])  # przeszycie górnego brzegu
    # Przeszycie rozporka ("J") pod paskiem.
    parts += stitches(obj, [(0.035, 0.4, 0.5), (0.035, 0.4, 0.44), (0.02, 0.4, 0.415), (-0.0, 0.4, 0.41)])
    for s in (1, -1):
        # Mały promień wokół własnej nogawki - inaczej przykleiłaby się też do drugiej nogi.
        parts.append(hugging_band("Cuff", obj, 0.205, 0.065, 0.012, 0.024, material("overalls"),
                                  center_x=s * 0.175, radius=0.15))
    return parts


def build_straps(shirt):
    """Płaskie, szerokie szelki: od śliniaka przez ramię na plecy, z mosiężną klamrą i guzikiem."""
    parts = []
    for s in (1, -1):
        pts = [(s * 0.165, 0.21, 0.89), (s * 0.18, 0.19, 0.96), (s * 0.195, 0.12, 1.03), (s * 0.2, 0.02, 1.07),
               (s * 0.2, -0.08, 1.05), (s * 0.18, -0.16, 0.99), (s * 0.15, -0.2, 0.9), (s * 0.13, -0.21, 0.8)]
        parts.append(strap("Strap", pts, 0.08, shirt, material("overalls"), offset=0.016, thickness=0.016))
        parts.append(ellipsoid("Button", (s * 0.165, 0.245, 0.9), (0.024, 0.011, 0.024), material("brass"),
                               segments=12))
    return parts


def surface_point(target, z, angle):
    """Punkt na powierzchni `target` na wysokości z, w kierunku `angle` (0 = przód, +Y)."""
    d = Vector((math.sin(angle), math.cos(angle), 0))
    ok, loc, normal, _ = target.ray_cast(Vector((0, 0, z)) + d * 2.0, -d)
    return (loc, normal) if ok else (Vector((0, 0, z)) + d * 0.3, d)


def hugging_band(name, target, z, height, offset, thickness, mat, center_x=0.0, radius=0.6):
    """Opaska (pas, mankiet) dokładnie przylegająca do powierzchni `target`."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=height, end_fill_type="NOTHING",
                                        location=(center_x, 0, z))
    band = bpy.context.active_object
    band.name = name
    sub = band.modifiers.new("cuts", "SUBSURF")
    sub.levels = 1
    sub.subdivision_type = "SIMPLE"
    sw = band.modifiers.new("hug", "SHRINKWRAP")
    sw.target = target
    # Rzut wzdłuż normalnych opaski (poziomo, do środka) - pas zostaje na stałej wysokości.
    sw.wrap_method = "PROJECT"
    sw.use_negative_direction = True
    sw.use_positive_direction = True
    sw.offset = offset
    so = band.modifiers.new("thick", "SOLIDIFY")
    so.thickness = thickness
    so.offset = 1.0
    for m in list(band.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    band.data.materials.append(mat)
    for p in band.data.polygons:
        p.use_smooth = True
    return band


def build_belt(overalls):
    parts = [hugging_band("Belt", overalls, 0.56, 0.075, 0.006, 0.022, material("belt"))]
    loc, n = surface_point(overalls, 0.56, 0.0)
    parts.append(add_mesh("Buckle", lambda: bpy.ops.mesh.primitive_cube_add(size=1), material("metal"),
                          location=loc + n * 0.03, scale=(0.13, 0.022, 0.09), bevel=0.01))
    parts.append(add_mesh("BuckleInner", lambda: bpy.ops.mesh.primitive_cube_add(size=1), material("belt"),
                          location=loc + n * 0.043, scale=(0.085, 0.012, 0.05)))
    for s in (1, -1):
        a = s * math.radians(55)
        loc, n = surface_point(overalls, 0.52, a)
        parts.append(add_mesh("Pouch", lambda: bpy.ops.mesh.primitive_cube_add(size=1), material("belt"),
                              location=loc + n * 0.045, scale=(0.09, 0.05, 0.11), rot=(0, 0, -a), bevel=0.012))
    return parts


def build_hammer(overalls):
    """Rączka narzędzia wystająca z prawej sakiewki (jak na obrazku)."""
    loc, n = surface_point(overalls, 0.52, math.radians(40))
    base = loc + n * 0.05
    return [add_mesh("ToolHandle", lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.014, depth=0.1),
                     material("belt"), location=base + Vector((0, 0, 0.07)))]


def build_boots():
    o = metaball("Boots")
    for s in (1, -1):
        # Duże, toporne buciory - szersze niż nogawka, czubek wysunięty do przodu.
        mb_ellipsoid(o, (s * 0.175, 0.05, 0.09), (0.122, 0.19, 0.075))
        mb_capsule(o, (s * 0.175, -0.01, 0.1), (s * 0.175, -0.01, 0.17), 0.108)
    parts = [finish_metaball(o, material("boots"), 4000)]
    soles = metaball("Soles", 0.01)
    for s in (1, -1):
        mb_ellipsoid(soles, (s * 0.175, 0.05, 0.034), (0.13, 0.2, 0.034))  # gruba, jasna podeszwa
    parts.append(finish_metaball(soles, material("sole"), 2000))
    return parts


# --- Szkielet --------------------------------------------------------------------------------

BONES = [
    # nazwa, rodzic, głowa, ogon
    ("Hips", None, (0, 0, 0.47), (0, 0, 0.6)),
    ("Spine", "Hips", (0, 0, 0.6), (0, 0, 0.8)),
    ("Chest", "Spine", (0, 0, 0.8), (0, 0, 1.0)),
    ("Neck", "Chest", (0, 0, 1.0), (0, 0, 1.1)),
    ("Head", "Neck", (0, 0, 1.1), (0, 0, 1.6)),
]
for _s, _p in ((1, "Right"), (-1, "Left")):
    BONES += [
        (_p + "Shoulder", "Chest", (_s * 0.06, 0, 0.95), (_s * 0.28, 0, 0.945)),
        (_p + "UpperArm", _p + "Shoulder", (_s * 0.28, 0, 0.945), (_s * 0.5, 0, 0.94)),
        (_p + "LowerArm", _p + "UpperArm", (_s * 0.5, 0, 0.94), (_s * 0.73, 0, 0.94)),
        (_p + "Hand", _p + "LowerArm", (_s * 0.73, 0, 0.94), (_s * 0.92, 0, 0.935)),
        (_p + "UpperLeg", "Hips", (_s * 0.175, 0, 0.47), (_s * 0.175, 0, 0.28)),
        (_p + "LowerLeg", _p + "UpperLeg", (_s * 0.175, 0, 0.28), (_s * 0.175, 0, 0.09)),
        (_p + "Foot", _p + "LowerLeg", (_s * 0.175, 0, 0.09), (_s * 0.175, 0.18, 0.03)),
    ]


def build_armature():
    arm_data = bpy.data.armatures.new("WorkerArmature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in BONES:
        b = arm_data.edit_bones.new(name)
        if "Arm" in name or "Hand" in name:
            head, tail = arm_down(head), arm_down(tail)
        b.head = head
        b.tail = tail
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


ARM_DOWN_DEG = 55.0
ARM_PIVOT = (0.28, 0.945)  # (|x|, z) stawu barkowego


def arm_down(co, weight=1.0):
    """Obraca punkt ręki (zbudowanej w T-pose) w dół wokół barku - do A-pose jak na referencji."""
    s = 1.0 if co[0] >= 0 else -1.0
    ang = math.radians(ARM_DOWN_DEG) * weight
    px, pz = s * ARM_PIVOT[0], ARM_PIVOT[1]
    dx, dz = co[0] - px, co[2] - pz
    c, si = math.cos(ang), math.sin(ang)
    # Obrót wokół osi Y (przód-tył): prawa ręka (+X) i lewa (-X) w dół.
    return Vector((px + dx * c + s * dz * si, co[1], pz - s * dx * si + dz * c))


def lower_arms_mesh(body):
    """Opuszcza ręce w siatce; przy barku płynne przejście, żeby rękaw ładnie się zginał."""
    for v in body.data.vertices:
        x, z = abs(v.co.x), v.co.z
        if z < 0.8 or x < 0.29:
            continue
        t = min(1.0, (x - 0.29) / 0.11)
        w = t * t * (3 - 2 * t)
        v.co = arm_down(v.co, w)
    body.data.update()


# --- Animacje ---------------------------------------------------------------------------------
# Każda poza to słownik: kość -> (obrót X, Y, Z w stopniach, w osiach postaci[, przesunięcie]).
# Osie: X w prawo (dodatni obrót: noga/ręka do przodu), Y do przodu (ujemny dla prawej ręki:
# ręka w bok i w górę), Z w górę (skręt). Obrót kości-dziecka liczy się względem rodzica.
# Kość Head nie jest animowana - pochyla ją gra (WorkerRig.set_head_pitch).

ANIM_FPS = 30


def _sym(pose, bone, rx=0.0, ry=0.0, rz=0.0, right=None, left=None):
    """Ten sam ruch dla obu stron (Y i Z lustrzane); right/left nadpisują obrót X danej strony."""
    for side, s in (("Right", 1), ("Left", -1)):
        x = rx
        if side == "Right" and right is not None:
            x = right
        if side == "Left" and left is not None:
            x = left
        pose[side + bone] = (x, s * ry, s * rz)


def pose_idle(t):
    b = math.sin(t * 2 * math.pi)
    p = {"Chest": (1.5 * b, 0, 0), "Spine": (-0.8 * b, 0, 0), "Hips": (0, 0, 0, (0, 0, 0.004 * b))}
    _sym(p, "UpperArm", 2.0, -2.0 * b, 0)
    _sym(p, "LowerArm", 8.0)
    return p


def pose_walk(t):
    ph = t * 2 * math.pi
    s, c = math.sin(ph), math.cos(ph)
    p = {
        "Hips": (0, 0, 6 * s, (0, 0, 0.022 * math.cos(2 * ph) - 0.012)),
        "Spine": (-4, 0, -4 * s),
        "Chest": (0, 0, -5 * s),
    }
    kr = -(8 + 42 * max(0.0, c))
    kl = -(8 + 42 * max(0.0, -c))
    p["RightUpperLeg"] = (28 * s, 0, 0)
    p["LeftUpperLeg"] = (-28 * s, 0, 0)
    p["RightLowerLeg"] = (kr, 0, 0)
    p["LeftLowerLeg"] = (kl, 0, 0)
    p["RightFoot"] = (-0.45 * (28 * s + kr), 0, 0)
    p["LeftFoot"] = (-0.45 * (-28 * s + kl), 0, 0)
    _sym(p, "UpperArm", right=-24 * s, left=24 * s)
    _sym(p, "LowerArm", 18.0)
    return p


CROUCH_DROP = 0.165


def pose_crouch(t):
    b = math.sin(t * 2 * math.pi)
    p = {"Hips": (0, 0, 0, (0, 0.02, -CROUCH_DROP)), "Spine": (-22 + b, 0, 0), "Chest": (-6, 0, 0),
         "Neck": (18, 0, 0)}
    _sym(p, "UpperLeg", 62)
    _sym(p, "LowerLeg", -112)
    _sym(p, "Foot", 50)
    _sym(p, "UpperArm", 32, -6, 0)
    _sym(p, "LowerArm", 35)
    return p


def pose_crouch_walk(t):
    ph = t * 2 * math.pi
    s, c = math.sin(ph), math.cos(ph)
    p = pose_crouch(0)
    p["Hips"] = (0, 0, 5 * s, (0, 0.02, -CROUCH_DROP + 0.012 * math.cos(2 * ph)))
    p["RightUpperLeg"] = (62 + 20 * s, 0, 0)
    p["LeftUpperLeg"] = (62 - 20 * s, 0, 0)
    p["RightLowerLeg"] = (-112 - 18 * max(0.0, c), 0, 0)
    p["LeftLowerLeg"] = (-112 - 18 * max(0.0, -c), 0, 0)
    _sym(p, "UpperArm", right=32 - 12 * s, left=32 + 12 * s)
    return p


def pose_sit(t):
    p = {"Spine": (-4, 0, 0)}
    _sym(p, "UpperLeg", 88)
    _sym(p, "LowerLeg", -85)
    _sym(p, "UpperArm", 40, -5, 0)
    _sym(p, "LowerArm", 40)
    return p


def _mix(a, b, k):
    out = {}
    for name in set(a) | set(b):
        va = a.get(name, (0, 0, 0))
        vb = b.get(name, (0, 0, 0))
        rot = tuple(x + (y - x) * k for x, y in zip(va[:3], vb[:3]))
        la = va[3] if len(va) > 3 else (0, 0, 0)
        lb = vb[3] if len(vb) > 3 else (0, 0, 0)
        out[name] = rot + (tuple(x + (y - x) * k for x, y in zip(la, lb)),)
    return out


def _keys(keys, t):
    """Płynne przejście między pozami-kluczami [(czas 0..1, poza), ...]."""
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            k = 0.0 if t1 <= t0 else (t - t0) / (t1 - t0)
            return _mix(a, b, k * k * (3 - 2 * k))
    return keys[-1][1]


def _jump_keys():
    load = {"Hips": (0, 0, 0, (0, 0, -0.07)), "Spine": (-12, 0, 0)}
    _sym(load, "UpperLeg", 30)
    _sym(load, "LowerLeg", -55)
    _sym(load, "Foot", 25)
    _sym(load, "UpperArm", -25, 0, 0)
    _sym(load, "LowerArm", 15)
    push = {"Hips": (0, 0, 0, (0, 0, 0.02)), "Spine": (4, 0, 0)}
    _sym(push, "UpperLeg", -4)
    _sym(push, "LowerLeg", -4)
    _sym(push, "Foot", -30)
    _sym(push, "UpperArm", 25, -55, 0)
    _sym(push, "LowerArm", 20)
    air = {"Spine": (-6, 0, 0)}
    _sym(air, "UpperLeg", right=45, left=25)
    _sym(air, "LowerLeg", right=-75, left=-50)
    _sym(air, "Foot", 10)
    _sym(air, "UpperArm", 10, -65, 0)
    _sym(air, "LowerArm", 25)
    return [(0.0, {}), (0.15, load), (0.35, push), (0.7, air), (1.0, air)]


def pose_jump(t):
    return _keys(_jump_keys(), t)


def _fall_keys():
    tip = {"Hips": (35, 0, 0, (0, -0.04, -0.05)), "Spine": (-10, 0, 0), "Neck": (-15, 0, 0)}
    _sym(tip, "UpperLeg", 25)
    _sym(tip, "LowerLeg", -20)
    _sym(tip, "UpperArm", 30, -75, 0)
    _sym(tip, "LowerArm", 20)
    ground = {"Hips": (90, 0, 0, (0, -0.06, -0.225)), "Spine": (4, 0, 0), "Neck": (-10, 0, 0)}
    _sym(ground, "UpperLeg", 40)
    _sym(ground, "LowerLeg", -65)
    _sym(ground, "Foot", 20)
    _sym(ground, "UpperArm", -10, -80, 0)
    _sym(ground, "LowerArm", 25)
    bounce = _mix(ground, tip, 0.12)
    return [(0.0, {}), (0.25, tip), (0.55, ground), (0.7, bounce), (0.85, ground), (1.0, ground)]


def pose_fall(t):
    return _keys(_fall_keys(), t)


# nazwa, funkcja pozy, liczba klatek, czy w pętli
ANIMATIONS = [
    ("Idle", pose_idle, 72, True),
    ("Walk", pose_walk, 30, True),
    ("Crouch", pose_crouch, 60, True),
    ("CrouchWalk", pose_crouch_walk, 36, True),
    ("Jump", pose_jump, 20, False),
    ("Fall", pose_fall, 30, False),
    ("Sit", pose_sit, 10, True),
]


def build_animations(arm):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.context.scene.render.fps = ANIM_FPS
    rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
    arm.animation_data_create()
    for name, fn, frames, loop in ANIMATIONS:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        last = frames if loop else frames - 1
        for f in range(0, last + 1):
            pose = fn(f / frames if loop else f / max(1, frames - 1))
            for pb in arm.pose.bones:
                if pb.name == "Head":
                    continue
                v = pose.get(pb.name, (0, 0, 0))
                d = Euler([math.radians(a) for a in v[:3]], "XYZ").to_quaternion()
                rq = rest[pb.name]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = rq.inverted() @ d @ rq
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if pb.name == "Hips":
                    loc = Vector(v[3]) if len(v) > 3 else Vector((0, 0, 0))
                    pb.location = rq.inverted() @ loc
                    pb.keyframe_insert("location", frame=f)
        # Każda animacja na osobnym torze NLA - eksporter glTF bierze z nich wszystkie.
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.ops.object.mode_set(mode="OBJECT")


# --- Podgląd ----------------------------------------------------------------------------------

def render_previews(folder):
    os.makedirs(folder, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    scene.world = world
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, 0.88))
    views = {
        "front": Vector((0, 5, 0.88)),
        "side": Vector((-5, 0, 0.88)),
        "back": Vector((0, -5, 0.88)),
        "three_quarter": Vector((-3.4, 3.4, 1.6)),
        "face": Vector((0.6, 5, 1.32)),
    }
    for name, pos in views.items():
        cam.location = pos
        look = (Vector((0, 0, 1.3)) if name == "face" else target) - pos
        cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
        cam_data.ortho_scale = 0.9 if name == "face" else 2.0
        scene.render.filepath = os.path.join(folder, name + ".png")
        bpy.ops.render.render(write_still=True)


# --- Główny przebieg ------------------------------------------------------------------------------

def join_parts(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    # Współrzędne wierzchołków = współrzędne świata (inaczej opuszczanie rąk liczy się źle).
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def copy_weights(dst, src):
    """Wagi kości dla dodatków (pas, kieszeń, mankiety...) - z najbliższego miejsca ciała."""
    bpy.ops.object.select_all(action="DESELECT")
    dst.select_set(True)
    bpy.context.view_layer.objects.active = dst
    mod = dst.modifiers.new("weights", "DATA_TRANSFER")
    mod.object = src
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    mod.vert_mapping = "POLYINTERP_NEAREST"
    mod.layers_vgroup_select_src = "ALL"
    mod.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.datalayout_transfer(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def main():
    reset_scene()
    # Trzy grupy z różnym sposobem liczenia wag:
    #  core  - ciało i ubranie (wagi automatyczne Blendera),
    #  head  - kask, nos, wąs, włosy (sztywno na kości Head),
    #  extra - drobne dodatki (wagi skopiowane z najbliższego miejsca ciała),
    #  belt  - pas z sakiewkami (sztywno na kości Hips).
    head = []
    head += build_nose_and_blush()
    head += build_moustache()
    head.append(build_hair())
    head.append(fuse(build_helmet(), "Helmet", 16000, voxel=0.0035, smooth=3))
    shirt_parts = build_shirt()
    shirt = shirt_parts[0]
    overall_parts = build_overalls()
    overalls = overall_parts[0]
    boots = build_boots()
    extra = shirt_parts[1:] + overall_parts[1:]
    extra += build_straps(shirt)
    belt = build_belt(overalls) + build_hammer(overalls)
    skin = fuse([build_skin()] + build_hands(), "Skin", 20000)
    core = join_parts([skin, shirt, overalls] + boots, "Worker")
    head_obj = join_parts(head, "HeadParts")
    extra_obj = join_parts(extra, "Extras")
    belt_obj = join_parts(belt, "BeltParts")
    for obj in (core, head_obj, extra_obj, belt_obj):
        lower_arms_mesh(obj)

    arm = build_armature()
    bpy.ops.object.select_all(action="DESELECT")
    core.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    vg = head_obj.vertex_groups.new(name="Head")
    vg.add(list(range(len(head_obj.data.vertices))), 1.0, "REPLACE")
    vg = belt_obj.vertex_groups.new(name="Hips")  # pas sztywno na biodrach (nie ciągnie się za udami)
    vg.add(list(range(len(belt_obj.data.vertices))), 1.0, "REPLACE")
    copy_weights(extra_obj, core)

    body = join_parts([core, head_obj, extra_obj, belt_obj], "Worker")
    body.data.validate()
    print("tris:", sum(len(p.vertices) - 2 for p in body.data.polygons))
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 0.01 for g in v.groups))
    print("vertices without weights:", unweighted)

    if PREVIEW_DIR:
        render_previews(PREVIEW_DIR)
    build_animations(arm)

    bpy.ops.object.select_all(action="DESELECT")
    os.makedirs(os.path.dirname(os.path.abspath(OUT_GLB)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS")
    print("exported", OUT_GLB)


main()
