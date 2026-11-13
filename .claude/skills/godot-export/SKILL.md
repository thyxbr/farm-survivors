---
name: godot-export
description: Godot-specific Blender export favoring GLTF/GLB with correct scale, materials, animation clips, and collision shapes via MCP.
license: MIT
metadata:
  author: https://github.com/arjun988
  version: "1.0.0"
  domain: blender
  role: specialist
  triggers: Godot, Godot export, Godot GLTF, Godot GLB, Godot materials, Godot animation
  related-skills: export-pipeline, lod-pipeline, collision-proxy, asset-optimization, materials
---

# Godot Export

GLTF/GLB first. Clean nodes. Godot-friendly materials and animation.

## This Project (godot-3d)

See `../references/godot-3d-pipeline.md`. In short: `export()` in `tools/blender/build_assets.py` already
exports with `export_format='GLB', export_yup=True, export_apply=True`, no animations/cameras/lights,
to `assets/models/<name>.glb`. Front = -Y in Blender. Animation is code-driven on pivot empties, so
never add armatures/actions unless the user asks. Part and pivot names are referenced from `scripts/`
(grep before renaming). Godot import already has `generate_lods=true`. After exporting, run Godot
`--headless --path . --import` and the smoke test from the pipeline file.

## When to Use

- Shipping meshes/animations to Godot 4.x
- GLB single-file props and characters
- Simple collision companions

## Pre-Flight

1. `asset-optimization` PASS
2. Apply transforms; Y-up friendly hierarchy
3. Materials metallic-roughness compatible

## Format

| Case | Format |
|------|--------|
| Default | GLB |
| Editable sidecar textures | GLTF separate |

## Settings

```
Format: GLB
+Y Up
Apply Modifiers: ON (when final)
Animation: include when needed
```

## Hierarchy

- Root empty or object named for scene root
- Avoid deep useless empties
- Keep collision meshes clearly named `COL_` / `UCX_` style

## Materials

- Principled BSDF → GLTF PBR
- Pack images or keep relative paths consistent
- Emission only where intended

## Animation

- NLA or actions exported as clips
- Name actions `AN_[Clip]`
- Root motion documented if used

## Verify in Godot

- [ ] Scale
- [ ] Import materials
- [ ] Animation libraries
- [ ] Collision shapes

## Constraints

### MUST DO
- Prefer GLB unless project says otherwise
- Test import once
- Keep naming consistent with `naming-conventions.md`

### MUST NOT DO
- Rely on Blender-only shader nodes that do not export

## Reference Guide

| Topic | Reference | Load When |
|-------|-----------|----------|
| Godot Checklist | `references/godot-checklist.md` | When needed |
