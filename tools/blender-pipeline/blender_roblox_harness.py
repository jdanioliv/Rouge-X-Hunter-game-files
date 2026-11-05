"""
Blender 5.2 Roblox Asset Optimization & Export Engine
-----------------------------------------------------
Handles automatic mesh decimation, scale calibration, origin centering,
and Roblox-compliant FBX/OBJ export for Roblox Studio.
"""

import sys
import os
import argparse
import bpy
import bmesh

def clear_scene():
    """Removes all default objects (cubes, cameras, lights) from the scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_mesh(file_path):
    """Imports OBJ, FBX, or GLTF mesh into the scene."""
    ext = os.path.splitext(file_path)[1].lower()
    if ext == ".obj":
        bpy.ops.wm.obj_import(filepath=file_path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=file_path)
    elif ext in [".gltf", ".glb"]:
        bpy.ops.import_scene.gltf(filepath=file_path)
    else:
        raise ValueError(f"Unsupported format: {ext}")

    selected_objs = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    if not selected_objs:
        all_meshes = [o for o in bpy.data.objects if o.type == 'MESH']
        if all_meshes:
            return all_meshes[0]
        raise RuntimeError("No mesh objects found after import.")
    return selected_objs[0]

def count_triangles(obj):
    """Returns the total number of evaluated triangles in the mesh."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    tri_count = len(mesh.loop_triangles)
    eval_obj.to_mesh_clear()
    return tri_count

def optimize_mesh_for_roblox(obj, target_triangles=3000):
    """
    Decimates mesh if it exceeds target triangle count, cleans vertices,
    and recalculates outside normals.
    Roblox hard ceiling is 20,000 triangles, but competitive combat games
    require 1,000 to 4,000 triangles per asset.
    """
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Clean loose vertices and zero-area faces
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0001, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    current_tris = count_triangles(obj)
    print(f"[Harness] Initial mesh triangle count: {current_tris}")

    if current_tris > target_triangles:
        ratio = max(0.01, min(1.0, target_triangles / current_tris))
        print(f"[Harness] Applying Decimate modifier with ratio: {ratio:.4f} (target: {target_triangles} tris)")
        decimate_mod = obj.modifiers.new(name="Roblox_Decimate", type='DECIMATE')
        decimate_mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=decimate_mod.name)
        new_tris = count_triangles(obj)
        print(f"[Harness] Optimized mesh triangle count: {new_tris}")
    else:
        print("[Harness] Mesh is already within target budget; no decimation needed.")

    # Auto UV unwrap if mesh lacks UV coordinates
    if not obj.data.uv_layers:
        print("[Harness] Generating Smart UV Project unwrap...")
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
        bpy.ops.object.mode_set(mode='OBJECT')

def center_origin_for_roblox(obj, origin_type="BOTTOM"):
    """
    Sets origin to BOTTOM (ideal for weapons, character accessories, props)
    or CENTER (ideal for aura spheres, projectiles, hitbox triggers).
    """
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    if origin_type == "CENTER":
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    elif origin_type == "BOTTOM":
        # Calculate bounding box minimum Z
        bbox = [obj.matrix_world @ obj.data.vertices[v.index].co for v in obj.data.vertices]
        min_z = min(co.z for co in bbox)
        center_x = sum(co.x for co in bbox) / len(bbox)
        center_y = sum(co.y for co in bbox) / len(bbox)

        bpy.context.scene.cursor.location = (center_x, center_y, min_z)
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.context.scene.cursor.location = (0, 0, 0)
        obj.location = (0, 0, 0)

    # Apply all transforms (rotation, scale, location)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def export_roblox_fbx(output_path):
    """
    Exports clean FBX with Roblox Studio coordinate standards:
    Forward: -Z, Up: Y, Scale: 1.0 (apply all unit scale).
    Also saves a native .blend file alongside the .fbx so it can be opened
    directly in Blender by double-clicking without format errors!
    """
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    # 1. Export Roblox-compliant FBX
    bpy.ops.export_scene.fbx(
        filepath=output_path,
        check_existing=False,
        use_selection=True,
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options='FBX_SCALE_ALL',
        axis_forward='-Z',
        axis_up='Y',
        bake_space_transform=True,
        object_types={'MESH'},
        mesh_smooth_type='FACE'
    )
    print(f"[Harness] Successfully exported Roblox-ready FBX: {output_path}")

    # 2. Save native .blend file for instant double-click opening in Blender
    blend_path = os.path.splitext(output_path)[0] + ".blend"
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)
    print(f"[Harness] Successfully saved native Blender project: {blend_path}")

def main():
    # Parsing args passed after '--'
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
    else:
        args = []

    parser = argparse.ArgumentParser(description="Blender Roblox Asset Harness")
    parser.add_argument("--input", help="Path to input mesh file (.obj, .fbx, .gltf)", default=None)
    parser.add_argument("--script", help="Path to Python procedural generation script", default=None)
    parser.add_argument("--output", help="Path to output .fbx file", required=True)
    parser.add_argument("--max-tris", type=int, default=3000, help="Target triangle limit for Roblox")
    parser.add_argument("--origin", default="BOTTOM", choices=["BOTTOM", "CENTER"], help="Origin placement")

    parsed = parser.parse_args(args)

    clear_scene()

    if parsed.script:
        print(f"[Harness] Executing procedural script: {parsed.script}")
        with open(parsed.script, "r", encoding="utf-8") as f:
            code = f.read()
        exec(code, {"__name__": "__main__"})
        meshes = [o for o in bpy.data.objects if o.type == 'MESH']
        if not meshes:
            raise RuntimeError("Procedural script did not create any mesh objects.")
        active_obj = meshes[0]
    elif parsed.input:
        print(f"[Harness] Importing input mesh: {parsed.input}")
        active_obj = import_mesh(parsed.input)
    else:
        raise ValueError("Must provide either --input or --script")

    optimize_mesh_for_roblox(active_obj, target_triangles=parsed.max_tris)
    center_origin_for_roblox(active_obj, origin_type=parsed.origin)
    export_roblox_fbx(parsed.output)

if __name__ == "__main__":
    main()
