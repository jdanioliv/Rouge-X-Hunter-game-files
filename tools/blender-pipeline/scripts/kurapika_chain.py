"""
Kurapika's Judgement / Dowsing Chain Generator
Creates interconnected low-poly chain links terminating in a Nen dagger tip.
Designed for Blender 5.2 -> Roblox Studio
"""
import bpy
import bmesh
import math

# Create chain links
num_links = 6
link_radius = 0.25
link_thickness = 0.05
link_spacing = 0.35

links = []
for i in range(num_links):
    rot_x = math.radians(90) if i % 2 == 1 else 0
    bpy.ops.mesh.primitive_torus_add(
        major_radius=link_radius,
        minor_radius=link_thickness,
        major_segments=16,
        minor_segments=8,
        location=(0, 0, i * link_spacing),
        rotation=(rot_x, 0, 0)
    )
    link = bpy.context.active_object
    link.name = f"ChainLink_{i}"
    links.append(link)

# Create Judgement Chain dagger tip (small pointed blade)
bpy.ops.mesh.primitive_cone_add(
    vertices=4,
    radius1=0.2,
    radius2=0.0,
    depth=0.8,
    location=(0, 0, num_links * link_spacing + 0.35),
    rotation=(math.radians(180), 0, 0)
)
dagger = bpy.context.active_object
dagger.name = "DaggerTip"
links.append(dagger)

# Join all chain parts into single mesh
for obj in links:
    obj.select_set(True)
bpy.context.view_layer.objects.active = links[0]
bpy.ops.object.join()
