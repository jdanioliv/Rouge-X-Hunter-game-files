"""
Procedural Nen Aura Sphere Generator (Gon's Jajanken / Guanyin Bodhisattva Aura)
Designed for Blender 5.2 -> Roblox Studio
"""
import bpy
import bmesh
import math

# Create base aura sphere
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.5, location=(0, 0, 1.5))
sphere = bpy.context.active_object
sphere.name = "NenAuraSphere"

# Add aura noise spikes via Displace modifier
texture = bpy.data.textures.new("AuraNoise", type='CLOUDS')
texture.noise_scale = 0.6
texture.noise_depth = 2

displace = sphere.modifiers.new(name="AuraSpikes", type='DISPLACE')
displace.texture = texture
displace.strength = 0.35
bpy.ops.object.modifier_apply(modifier=displace.name)

# Create an outer aura ring (energy wave)
bpy.ops.mesh.primitive_torus_add(major_radius=2.2, minor_radius=0.12, location=(0, 0, 1.5))
ring = bpy.context.active_object
ring.name = "AuraRing"

# Join into single asset for Roblox import
sphere.select_set(True)
ring.select_set(True)
bpy.context.view_layer.objects.active = sphere
bpy.ops.object.join()
