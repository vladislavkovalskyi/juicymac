"""Juicy Mac icon set: glossy 3D icons rendered with Blender Cycles.

Usage: blender -b -P design/icons/render_icons.py -- <out_dir> [icon ...]
"""
import math
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/juicy-icons"
ONLY = set(argv[1:])
SIZE = 512


# ---------- scene ----------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scn.cycles.device = "GPU"
    except Exception:
        scn.cycles.device = "CPU"
    scn.cycles.samples = 128
    scn.cycles.use_denoising = True
    scn.render.film_transparent = True
    scn.render.resolution_x = SIZE
    scn.render.resolution_y = SIZE
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Punchy"

    world = bpy.data.worlds.new("W")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.82, 0.84, 0.9, 1)
    bg.inputs["Strength"].default_value = 0.55

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.5
    cam = bpy.data.objects.new("Cam", cam_data)
    scn.collection.objects.link(cam)
    az, el, dist = math.radians(28), math.radians(30), 12
    cam.location = (dist * math.cos(el) * math.sin(az), -dist * math.cos(el) * math.cos(az), dist * math.sin(el))
    look_at(cam, Vector((0, 0, 0.05)))
    scn.camera = cam

    area("Key", (-3, -3, 6), 9, 700, (1, 0.97, 0.93))
    area("Rim", (3, 4, 3), 5, 450, (0.85, 0.9, 1))
    area("Fill", (5, -2, 1), 6, 180, (1, 1, 1))

    # No baked contact shadow: it would reach the frame edge and crop into a visible square.
    # The UI draws its own soft shadow under the icon instead.


def look_at(obj, target):
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def area(name, loc, size, power, color):
    data = bpy.data.lights.new(name, "AREA")
    data.size = size
    data.energy = power
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    look_at(obj, Vector((0, 0, 0)))


# ---------- materials ----------

def hexc(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, 1)


def candy(name, c1, c2=None, axis="Z", rough=0.28, coat=0.8, metal=0.0, lo=-1.0, hi=1.0, emit=0.0):
    """Principled material with an object-space gradient from c1 (low) to c2 (high)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    if c2 is None:
        bsdf.inputs["Base Color"].default_value = hexc(c1)
        color_socket = None
    else:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        mr = nt.nodes.new("ShaderNodeMapRange")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        nt.links.new(sep.outputs[axis], mr.inputs["Value"])
        mr.inputs["From Min"].default_value = lo
        mr.inputs["From Max"].default_value = hi
        nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
        ramp.color_ramp.elements[0].color = hexc(c1)
        ramp.color_ramp.elements[1].color = hexc(c2)
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        color_socket = ramp.outputs["Color"]
    if emit:
        if color_socket is not None:
            nt.links.new(color_socket, bsdf.inputs["Emission Color"])
        else:
            bsdf.inputs["Emission Color"].default_value = hexc(c1)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m


def glass(name="Glass", tint="#EAF2FF", rough=0.04):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexc(tint)
    b.inputs["Transmission Weight"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    b.inputs["IOR"].default_value = 1.35
    return m


def chrome(name="Chrome", c="#D9DEE8"):
    return candy(name, c, rough=0.18, coat=0.0, metal=1.0)


# ---------- geometry helpers ----------

def apply(obj, mat, bevel=0.0, segs=6, smooth=True):
    if bevel:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segs
        mod.limit_method = "ANGLE"
    if smooth:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    obj.data.materials.append(mat)
    return obj


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.1, segs=6):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return apply(o, mat, bevel, segs)


def cyl(r, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.05, verts=96, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot, vertices=verts)
    return apply(bpy.context.active_object, mat, bevel)


def sphere(r, loc=(0, 0, 0), mat=None, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=64, ring_count=32)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    return o


def torus(R, r, loc=(0, 0, 0), rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=96, minor_segments=32)
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    return o


def extrude(points, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.06):
    me = bpy.data.meshes.new("poly")
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in points]
    face = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, depth), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("poly", me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    return apply(o, mat, bevel, 5)


def group(parts, rot):
    root = bpy.data.objects.new("Root", None)
    bpy.context.scene.collection.objects.link(root)
    for p in parts:
        p.parent = root
    root.rotation_euler = rot
    return root


# ---------- icons ----------

def icon_juice():
    g = glass()
    cyl(0.78, 1.9, (0, 0, 0), mat=glass("Cup", "#FFFFFF", 0.02), bevel=0.06, r2=0.95)
    juice = candy("Juice", "#FF4A10", "#FFB21F", lo=-0.9, hi=0.6, rough=0.15, coat=0.3, emit=0.35)
    cyl(0.7, 1.35, (0, 0, -0.26), mat=juice, bevel=0.04, r2=0.83)
    straw = candy("Straw", "#FF3D6E", "#FF8FB0", rough=0.3)
    cyl(0.07, 2.5, (0.3, 0.1, 0.55), rot=(math.radians(-8), math.radians(18), 0), mat=straw, bevel=0.0, verts=32)
    peel = candy("Peel", "#FF7A00", "#FFB02E", axis="X", lo=-0.5, hi=0.5)
    flesh = candy("Flesh", "#FFD76A", "#FFB43A", axis="X", lo=-0.4, hi=0.4, rough=0.35)
    rot = (math.radians(90), 0, math.radians(-35))
    cyl(0.52, 0.16, (-0.62, -0.52, 0.95), rot=rot, mat=peel, bevel=0.04)
    cyl(0.44, 0.2, (-0.62, -0.52, 0.95), rot=rot, mat=flesh, bevel=0.03)
    for i in range(3):
        sphere(0.05 + i * 0.015, (0.2 - i * 0.3, -0.62, -0.5 + i * 0.35), glass("Bubble", "#FFFFFF"))


def icon_cpu():
    body = candy("Chip", "#3B2BD9", "#8B5CFF", axis="X", lo=-1.1, hi=1.1)
    box((2.0, 2.0, 0.38), (0, 0, -0.3), mat=body, bevel=0.16)
    top = candy("Die", "#1B1640", "#3A2F8F", axis="Y", lo=-0.7, hi=0.7, rough=0.2)
    box((1.15, 1.15, 0.14), (0, 0, -0.04), mat=top, bevel=0.08)
    glow = candy("Glow", "#6EE7FF", emit=4.0, rough=0.3)
    box((0.62, 0.1, 0.06), (0, 0.18, 0.05), mat=glow, bevel=0.03)
    box((0.62, 0.1, 0.06), (0, -0.05, 0.05), mat=glow, bevel=0.03)
    box((0.36, 0.1, 0.06), (-0.13, -0.28, 0.05), mat=glow, bevel=0.03)
    pin = chrome("Pin", "#F2D38A")
    for i in range(5):
        t = -0.64 + i * 0.32
        box((0.14, 0.34, 0.1), (t, 1.13, -0.34), mat=pin, bevel=0.04)
        box((0.14, 0.34, 0.1), (t, -1.13, -0.34), mat=pin, bevel=0.04)
        box((0.34, 0.14, 0.1), (1.13, t, -0.34), mat=pin, bevel=0.04)
        box((0.34, 0.14, 0.1), (-1.13, t, -0.34), mat=pin, bevel=0.04)


def icon_memory():
    rot = (0, 0, math.radians(-12))
    board = candy("Board", "#0FA36B", "#5BE3A1", axis="X", lo=-1.4, hi=1.4)
    grp = []
    grp.append(box((2.7, 1.05, 0.14), (0, 0, -0.35), mat=board, bevel=0.07))
    chip = candy("RamChip", "#101820", "#2A3A48", axis="Y", rough=0.25)
    for i in range(4):
        grp.append(box((0.5, 0.52, 0.12), (-0.93 + i * 0.62, 0.1, -0.22), mat=chip, bevel=0.05))
    gold = chrome("Gold", "#F5C451")
    for i in range(12):
        grp.append(box((0.12, 0.2, 0.05), (-1.1 + i * 0.2, -0.43, -0.27), mat=gold, bevel=0.02))
    notch = candy("Notch", "#FFFFFF", rough=0.3)
    grp.append(box((0.08, 0.26, 0.16), (0.12, -0.44, -0.35), mat=notch, bevel=0.03))
    group(grp, rot).scale = (1.25, 1.25, 1.25)


def icon_disk():
    mats = [candy("D1", "#0C8CE9", "#38C8FF", axis="X", lo=-1, hi=1),
            candy("D2", "#1A6DF0", "#56B4FF", axis="X", lo=-1, hi=1),
            candy("D3", "#2C4DE0", "#6C8CFF", axis="X", lo=-1, hi=1)]
    for i, m in enumerate(mats):
        z = -0.62 + i * 0.52
        cyl(1.0, 0.4, (0, 0, z), mat=m, bevel=0.14)
        led = candy("Led%d" % i, "#7CFFB2" if i else "#FFD15C", emit=6.0)
        sphere(0.07, (0.55, -0.83, z), led)


FAN_COLORS = {
    # name: (frame low, frame high, blade root, blade tip, hub cap)
    "ice": ("#C9DBFF", "#F7FAFF", "#3B6BFF", "#2EE6FF", "#FF8A1F"),
    "juice": ("#2B2D3A", "#4C5068", "#FF6A13", "#FFC23D", "#FFFFFF"),
    "mint": ("#D7E4F5", "#FFFFFF", "#0FA3C8", "#5CF0B4", "#FF8A1F"),
}


def fan_blade_points(steps=10):
    lead, trail = [], []
    for i in range(steps + 1):
        t = i / steps
        r = 0.3 + 0.66 * t
        a1 = 0.55 * t
        a2 = 0.55 * t + 0.42 + 0.3 * t
        lead.append((r * math.cos(a1), r * math.sin(a1)))
        trail.append((r * math.cos(a2), r * math.sin(a2)))
    return lead + trail[::-1]


def fan_frame(half, hole, depth, mat, n=128):
    """Square plate with a round hole, built from clean quads (no boolean)."""
    me = bpy.data.meshes.new("frame")
    bm = bmesh.new()
    inner, outer = [], []
    for i in range(n):
        a = 2 * math.pi * i / n + math.pi / 4
        c, s = math.cos(a), math.sin(a)
        k = half / max(abs(c), abs(s))
        inner.append(bm.verts.new((hole * c, hole * s, -depth / 2)))
        outer.append(bm.verts.new((k * c, k * s, -depth / 2)))
    faces = [bm.faces.new((inner[i], outer[i], outer[(i + 1) % n], inner[(i + 1) % n])) for i in range(n)]
    res = bmesh.ops.extrude_face_region(bm, geom=faces)
    top = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, depth), verts=top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("frame", me)
    bpy.context.scene.collection.objects.link(o)
    return apply(o, mat, 0.08, 6)


def icon_fan(variant="juice"):
    f_lo, f_hi, b_lo, b_hi, cap_c = FAN_COLORS[variant]
    scn = bpy.context.scene
    scn.camera.data.ortho_scale = 3.9
    parts = []

    frame_m = candy("Frame", f_lo, f_hi, axis="Y", lo=-1.3, hi=1.3, rough=0.22)
    parts.append(fan_frame(1.15, 1.0, 0.42, frame_m))

    screw = chrome("Screw", "#C8D0DC")
    for sx in (-0.88, 0.88):
        for sy in (-0.88, 0.88):
            parts.append(cyl(0.09, 0.46, (sx, sy, 0), mat=screw, bevel=0.03, verts=32))

    blade_m = candy("Blade", b_lo, b_hi, axis="X", lo=-0.2, hi=1.0, rough=0.18)
    for i in range(7):
        a = i * 2 * math.pi / 7
        b = extrude(fan_blade_points(), 0.07, (0, 0, -0.035), (0, 0, a), blade_m, bevel=0.025)
        b.rotation_mode = "ZYX"
        b.rotation_euler = (math.radians(16), 0, a)
        parts.append(b)

    hub_m = candy("Hub", "#FFFFFF", "#E4EAF4", rough=0.2)
    parts.append(cyl(0.34, 0.34, (0, 0, 0), mat=hub_m, bevel=0.1))
    cap = candy("Cap", cap_c, rough=0.15)
    parts.append(cyl(0.16, 0.36, (0, 0, 0.02), mat=cap, bevel=0.06, verts=64))

    group(parts, (math.radians(72), 0, math.radians(18)))



def icon_temp():
    g = glass("TGlass", "#F4F8FF")
    cyl(0.3, 2.0, (0, 0, 0.25), mat=g, bevel=0.0, verts=64)
    sphere(0.3, (0, 0, 1.25), g)
    sphere(0.55, (0, 0, -0.85), g)
    red = candy("Mercury", "#FF2D55", "#FF7A45", lo=-1.2, hi=0.6, rough=0.12, emit=0.4)
    cyl(0.17, 1.35, (0, 0, -0.1), mat=red, bevel=0.0, verts=64)
    sphere(0.43, (0, 0, -0.85), red)
    tick = candy("Tick", "#FFFFFF", rough=0.3)
    for i in range(4):
        box((0.22, 0.05, 0.05), (0.38, -0.05, 0.05 + i * 0.3), mat=tick, bevel=0.02)


def icon_battery():
    rot = (0, 0, math.radians(-8))
    shell = glass("Shell", "#EEF4FF", rough=0.06)
    a = box((2.5, 1.15, 1.15), (-0.12, 0, 0), mat=shell, bevel=0.3, segs=8)
    fill = candy("Charge", "#23C55E", "#B6F36A", axis="X", lo=-1.2, hi=0.6, rough=0.18, emit=0.3)
    b = box((1.6, 0.9, 0.9), (-0.52, 0, 0), mat=fill, bevel=0.22, segs=8)
    cap = candy("Cap", "#D9DEE8", "#FFFFFF", rough=0.2)
    c = box((0.22, 0.5, 0.5), (1.24, 0, 0), mat=cap, bevel=0.08)
    group((a, b, c), rot)


def icon_bolt():
    m = candy("Bolt", "#FFB800", "#FF5A1F", axis="Y", lo=1.2, hi=-1.2, rough=0.18, emit=0.2)
    pts = [(0.25, 1.35), (-0.75, -0.1), (-0.05, -0.1), (-0.35, -1.35), (0.8, 0.25), (0.08, 0.25), (0.45, 1.35)]
    extrude(pts, 0.42, (0, 0.2, 0), (math.radians(90), 0, math.radians(-20)), m, bevel=0.1)


def icon_slice():
    rot = (math.radians(58), 0, math.radians(-18))
    peel = candy("Peel", "#FF6A00", "#FFB02E", axis="X", lo=-1.2, hi=1.2)
    root = bpy.data.objects.new("SliceRoot", None)
    bpy.context.scene.collection.objects.link(root)
    parts = [cyl(1.2, 0.3, (0, 0, 0), mat=peel, bevel=0.1)]
    pith = candy("Pith", "#FFF3D6", rough=0.5, coat=0.1)
    parts.append(cyl(1.04, 0.34, (0, 0, 0), mat=pith, bevel=0.05))
    flesh = candy("Flesh", "#FFB12E", "#FFD45C", axis="X", lo=-1, hi=1, rough=0.2, coat=1.0)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        pts = [(0.1, 0), (0.92 * math.cos(-0.33), 0.92 * math.sin(-0.33)), (0.95, 0), (0.92 * math.cos(0.33), 0.92 * math.sin(0.33))]
        parts.append(extrude(pts, 0.12, (0, 0, 0.13), (0, 0, a), flesh, bevel=0.04))
    for p in parts:
        p.parent = root
    root.rotation_euler = rot


ICONS = {
    "juice": icon_juice, "cpu": icon_cpu, "memory": icon_memory, "disk": icon_disk,
    "fan": icon_fan, "fan_ice": lambda: icon_fan("ice"), "fan_juice": lambda: icon_fan("juice"), "fan_mint": lambda: icon_fan("mint"), "temp": icon_temp, "battery": icon_battery, "bolt": icon_bolt, "slice": icon_slice,
}

for name, build in ICONS.items():
    if ONLY and name not in ONLY:
        continue
    reset()
    build()
    bpy.context.scene.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name)
