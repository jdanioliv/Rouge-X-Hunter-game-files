#!/usr/bin/env python3
"""
Roblox Hunter x Hunter 3D & AI Asset Pipeline CLI
=================================================
Automates procedural 3D modeling, mesh decimation, and FBX export
for Roblox Studio using Blender 5.2 and local Ollama Qwen 2.5 Coder 32B.
"""

import os
import sys
import argparse
import subprocess
import json
import urllib.request

BLENDER_EXE = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")
EXPORTS_DIR = os.path.join(BASE_DIR, "exports")
IMPORTS_DIR = os.path.join(BASE_DIR, "imports")
HARNESS_ENGINE = os.path.join(BASE_DIR, "blender_roblox_harness.py")
OLLAMA_API = "http://127.0.0.1:11434/api/generate"
MODEL_NAME = "qwen2.5-coder:32b"

def run_blender_harness(script_path=None, input_path=None, output_path=None, max_tris=3000, origin="BOTTOM"):
    if not os.path.exists(BLENDER_EXE):
        print(f"[Error] Blender executable not found at: {BLENDER_EXE}")
        return False

    cmd = [
        BLENDER_EXE,
        "--background",
        "--python", HARNESS_ENGINE,
        "--",
        "--output", output_path,
        "--max-tris", str(max_tris),
        "--origin", origin
    ]

    if script_path:
        cmd.extend(["--script", script_path])
    elif input_path:
        cmd.extend(["--input", input_path])
    else:
        print("[Error] Either --script or --input must be specified.")
        return False

    print(f"[CLI] Running Blender pipeline...")
    result = subprocess.run(cmd)
    if result.returncode == 0:
        print(f"[CLI] Success! Exported to: {output_path}")
        return True
    else:
        print(f"[CLI] Blender failed with exit code: {result.returncode}")
        return False

def query_local_ai(prompt, system_prompt=None, model="qwen2.5-coder:32b"):
    """Sends a generation request to a local AI model (Qwen 2.5 Coder or DeepSeek-R1)."""
    full_prompt = prompt
    if system_prompt:
        full_prompt = f"{system_prompt}\n\nTask: {prompt}"

    payload = json.dumps({
        "model": model,
        "prompt": full_prompt,
        "stream": False
    }).encode("utf-8")

    req = urllib.request.Request(
        OLLAMA_API,
        data=payload,
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=300) as response:
            data = json.loads(response.read().decode("utf-8"))
            return data.get("response", "")
    except Exception as e:
        print(f"[Error] Failed to communicate with local AI ({model}): {e}")
        return None

def generate_procedural_script_with_ai(description, output_script_name, model="deepseek-r1:32b"):
    """Asks local AI (DeepSeek-R1 32B or Qwen 2.5 Coder 32B) to generate a Blender 5.2 Python script."""
    print(f"[CLI] Asking {model} to reason and design 3D asset: '{description}'...")
    system_prompt = (
        "You are an expert 3D technical artist writing Blender 5.2 Python (bpy) scripts for a Roblox Hunter x Hunter anime game.\n"
        "Rules:\n"
        "1. Write clean, standalone Python code using bpy and bmesh.\n"
        "2. Only output executable Python code inside a ```python ``` code block.\n"
        "3. Create stylized, low-poly geometry suitable for Roblox (weapons, Nen auras, props).\n"
        "4. Join all resulting mesh parts into a single active mesh object named 'RobloxAsset'."
    )
    
    response = query_local_ai(description, system_prompt, model=model)
    if not response:
        return None

    # If reasoning model (like DeepSeek-R1), strip <think>...</think> if present
    code = response
    if "</think>" in code:
        code = code.split("</think>")[1].strip()

    # Extract code between ```python and ```
    if "```python" in code:
        code = code.split("```python")[1].split("```")[0].strip()
    elif "```" in code:
        code = code.split("```")[1].split("```")[0].strip()

    script_path = os.path.join(SCRIPTS_DIR, f"{output_script_name}.py")
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(code)

    print(f"[CLI] Generated script saved to: {script_path}")
    return script_path

def main():
    parser = argparse.ArgumentParser(description="Roblox Hunter x Hunter 3D & AI Asset CLI")
    subparsers = parser.add_subparsers(dest="command")

    # Command: list
    subparsers.add_parser("list", help="List available procedural asset generation scripts")

    # Command: build
    build_parser = subparsers.add_parser("build", help="Build an FBX asset from an existing procedural script")
    build_parser.add_argument("name", help="Script name (e.g. nen_aura_sphere, kurapika_chain, killua_lightning)")
    build_parser.add_argument("--max-tris", type=int, default=3000, help="Max triangles for Roblox")
    build_parser.add_argument("--origin", default="CENTER", choices=["BOTTOM", "CENTER"], help="Origin location")

    # Command: optimize
    opt_parser = subparsers.add_parser("optimize", help="Optimize raw downloaded/generated mesh for Roblox")
    opt_parser.add_argument("input_file", help="Input mesh file path (.obj, .fbx, .gltf)")
    opt_parser.add_argument("--name", help="Output FBX name (defaults to input filename)", default=None)
    opt_parser.add_argument("--max-tris", type=int, default=3000, help="Max triangles for Roblox")
    opt_parser.add_argument("--origin", default="BOTTOM", choices=["BOTTOM", "CENTER"], help="Origin location")

    # Command: create-ai
    ai_parser = subparsers.add_parser("create-ai", help="Ask local AI (DeepSeek-R1 32B or Qwen 2.5 Coder 32B) to write and export a new 3D asset")
    ai_parser.add_argument("description", help="Description of the 3D Hunter x Hunter asset to model")
    ai_parser.add_argument("name", help="Identifier name for the asset (e.g. zoldyck_gate, greed_island_card)")
    ai_parser.add_argument("--model", default="deepseek-r1:32b", choices=["deepseek-r1:32b", "qwen2.5-coder:32b"], help="Local model to use")
    ai_parser.add_argument("--max-tris", type=int, default=3000)
    ai_parser.add_argument("--origin", default="CENTER", choices=["BOTTOM", "CENTER"])

    args = parser.parse_args()

    if args.command == "list":
        scripts = [f[:-3] for f in os.listdir(SCRIPTS_DIR) if f.endswith(".py")]
        print("\nAvailable Procedural Asset Scripts:")
        for s in scripts:
            print(f"  - {s}")
        print("\nRun: python harness_cli.py build <name> to export to FBX for Roblox.\n")

    elif args.command == "build":
        script_file = os.path.join(SCRIPTS_DIR, f"{args.name}.py")
        if not os.path.exists(script_file):
            print(f"[Error] Script not found: {script_file}")
            return
        output_fbx = os.path.join(EXPORTS_DIR, f"{args.name}.fbx")
        run_blender_harness(script_path=script_file, output_path=output_fbx, max_tris=args.max_tris, origin=args.origin)

    elif args.command == "optimize":
        if not os.path.exists(args.input_file):
            print(f"[Error] Input file not found: {args.input_file}")
            return
        base_name = args.name or os.path.splitext(os.path.basename(args.input_file))[0]
        output_fbx = os.path.join(EXPORTS_DIR, f"{base_name}_roblox.fbx")
        run_blender_harness(input_path=args.input_file, output_path=output_fbx, max_tris=args.max_tris, origin=args.origin)

    elif args.command == "create-ai":
        script_path = generate_procedural_script_with_ai(args.description, args.name, model=args.model)
        if script_path:
            output_fbx = os.path.join(EXPORTS_DIR, f"{args.name}.fbx")
            run_blender_harness(script_path=script_path, output_path=output_fbx, max_tris=args.max_tris, origin=args.origin)

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
