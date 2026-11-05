# Roblox Hunter x Hunter 3D & AI Asset Pipeline

100% Free, locally accelerated pipeline using **Blender 5.2**, **Ollama ROCm (AMD RX 7900 XTX 24GB)**, and **Qwen 2.5 Coder 32B**.

---

## What is Installed & Configured

1. **Ollama ROCm Server**: Running locally at `http://127.0.0.1:11434` with 24 GB VRAM on your RX 7900 XTX.
2. **Qwen 2.5 Coder 32B**: 19 GB downloaded GGUF weights, ready for offline inference.
3. **Aider CLI**: Terminal autonomous coding agent. Launch by double-clicking `run_aider.bat`.
4. **Continue.dev (VS Code)**: Extension installed and pre-configured for inline code completion and chat with your local 32B model.
5. **Lunacy**: Vector design app installed for offline Figma (`.fig`) UI/HUD creation.
6. **Blender 5.2 Harness**: Generates and optimizes low-poly meshes for Roblox Studio.

---

## How to Use the Blender 3D Harness

All CLI commands are run from this folder:

### 1. View Available Procedural Scripts
```bash
python harness_cli.py list
```

### 2. Build Roblox-Ready FBX Assets
```bash
# Build Kurapika's chain links with dagger tip
python harness_cli.py build kurapika_chain --origin BOTTOM

# Build Killua's lightning mesh
python harness_cli.py build killua_lightning --origin CENTER

# Build Gon's Jajanken Nen aura sphere
python harness_cli.py build nen_aura_sphere --origin CENTER
```
Exported `.fbx` files are immediately available in the `exports/` folder, ready to drag-and-drop into **Roblox Studio**!

### 3. Ask Local AI to Design & Export a New 3D Asset
```bash
python harness_cli.py create-ai "A stylized anime Greed Island spell card with border bevels" greed_island_card
```
This prompts your local Qwen 2.5 Coder 32B to write a Blender Python (`bpy`) script, saves it into `scripts/`, executes it in Blender, cleans/decimates the mesh, and exports `exports/greed_island_card.fbx`.

### 4. Optimize Any Downloaded / AI-Generated 3D Mesh
If you download a 3D model (or generate one from an image) that has too many polygons for Roblox:
```bash
python harness_cli.py optimize "path/to/raw_mesh.obj" --max-tris 2500 --name "my_asset"
```
This automatically decimate-modifies the mesh to stay under your specified triangle budget (e.g. 2,500 tris) and exports a clean `.fbx`.

---

## How to Use Aider (Local Claude Code Equivalent)

Double click `run_aider.bat` in this directory.
Aider will launch in your terminal connected to your local Qwen 2.5 Coder 32B model.
You can give it multi-file instructions like:
> "Write a Roblox Luau module for managing Nen aura states (Ten, Ren, Zetsu, Gyo) with client replication via RemoteEvents."
