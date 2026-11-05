"""
Killua's Narukami / Godspeed Lightning Generator
Creates jagged 3D electric lightning bolts suitable for Roblox VFX parts.
Designed for Blender 5.2 -> Roblox Studio
"""
import bpy
import bmesh
import random
from mathutils import Vector

# Seed for reproducibility or variation
random.seed(42)

mesh = bpy.data.meshes.new("LightningBoltMesh")
obj = bpy.data.objects.new("KilluaLightning", mesh)
bpy.context.collection.objects.link(obj)

bm = bmesh.new()

segments = 8
height = 4.0
step_z = height / segments
current_pos = Vector((0.0, 0.0, 0.0))
radius = 0.08

prev_verts = None
for i in range(segments + 1):
    z = i * step_z
    offset_x = (random.random() - 0.5) * 0.8 if 0 < i < segments else 0
    offset_y = (random.random() - 0.5) * 0.8 if 0 < i < segments else 0
    center = Vector((offset_x, offset_y, z))

    # Cross section quad
    v1 = bm.verts.new(center + Vector((-radius, -radius, 0)))
    v2 = bm.verts.new(center + Vector(( radius, -radius, 0)))
    v3 = bm.verts.new(center + Vector(( radius,  radius, 0)))
    v4 = bm.verts.new(center + Vector((-radius,  radius, 0)))
    curr_verts = [v1, v2, v3, v4]

    if prev_verts:
        bm.faces.new([prev_verts[0], prev_verts[1], curr_verts[1], curr_verts[0]])
        bm.faces.new([prev_verts[1], prev_verts[2], curr_verts[2], curr_verts[1]])
        bm.faces.new([prev_verts[2], prev_verts[3], curr_verts[3], curr_verts[2]])
        bm.faces.new([prev_verts[3], prev_verts[0], curr_verts[0], curr_verts[3]])
    else:
        bm.faces.new([v4, v3, v2, v1])

    if i == segments:
        bm.faces.new([v1, v2, v3, v4])

    prev_verts = curr_verts

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(mesh)
bm.free()

bpy.context.view_layer.objects.active = obj
obj.select_set(True)
