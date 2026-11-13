---
name: blender-director
description: Use when starting any Blender asset task, planning a production pipeline, coordinating multiple disciplines, or matching a reference photo/concept art. Invoke for game-ready assets, hard surface, environment, character, creature, export, or any multi-skill Blender workflow.
license: MIT
metadata:
  author: https://github.com/arjun988
  version: "1.0.0-godot3d"
  domain: blender
  role: orchestrator
  triggers: Blender, 3D asset, game-ready, pipeline, workflow, plan, coordinate, technical artist
  related-skills: blender-modeler, prop-artist, environment-artist, character-artist, creature-artist, vegetation-artist, asset-optimization, godot-export, qa-review
---

# Blender Director

Senior Technical Director orchestrating game-ready Blender production for this project.
Trimmed for godot-3d: only the 20 installed skills are routed.

## Project Override (godot-3d) — read first

1. Read `../references/godot-3d-pipeline.md` before planning. It wins over anything below.
2. Execution = edit `tools/blender/build_assets.py` / `characters.py`, then run Blender **CLI in background**
   with filtered output. The Blender MCP is for inspection/experiments only (exporting through it crashed Blender).
3. Default direction: `lowpoly-style` + `stylized-style` + `fantasy-worlds` + `genre-rpg`,
   flat-colour materials, no textures/UVs, no armatures (pivot empties `LegL/LegR/Body/Head/ArmL/ArmR`).
4. Engine delivery is always `godot-export` (GLB). No manual LODs (Godot generates them on import).
5. Keep the production brief short (a few lines in chat). Iterate with `small` renders, final check at full size.

## Workflow

```
1. ANALYZE   → asset type, role in game (hero / standard / background), style, reference?
2. PLAN      → pick skills below, set triangle/material budget (pipeline table)
3. BRIEF     → 3–6 line brief in chat before editing scripts
4. EXECUTE   → edit builder function, build only that asset (ASSETS=<name>)
5. VALIDATE  → small renders while iterating; full-size + silhouette + TRIS at the end
6. DELIVER   → Godot import + smoke test, report tris and what changed
```

Read `../references/asset-pipeline.md`, `naming-conventions.md` or `validation-checklist.md` only
when the task needs them; `polycount-budgets.md` is superseded by the pipeline table.

## Skill Routing (installed skills only)

| Request | Primary | Supporting |
|---------|---------|------------|
| Props: furniture, containers, tools, chests, lamps | prop-artist | materials, lowpoly-style, asset-optimization |
| Buildings, ruins, walls, fences, modular pieces | environment-artist | prop-artist, procedural-modeling |
| Trees, bushes, foliage | vegetation-artist | procedural-modeling, lowpoly-style |
| Rocks, varied/repeated pieces, scatter-like variation | procedural-modeling | environment-artist |
| Humans/NPCs (knight, elder, merchant) | character-artist | character-archetypes, stylized-style |
| Monsters, animals, goblins, slimes | creature-artist | character-archetypes, stylized-style |
| Race/role look (knight, mage, rogue, orc…) | character-archetypes | character-artist, fantasy-worlds |
| Region / loot / RPG readability | genre-rpg | fantasy-worlds, materials |
| Medieval / fantasy flavour | fantasy-worlds | genre-rpg |
| Palette, material colours, metal vs cloth reads | materials | stylized-style |
| Shape language, exaggeration, appeal | stylized-style | lowpoly-style |
| Triangle/material budgets, cleanup | asset-optimization | qa-review |
| Collision shapes for Godot | collision-proxy | godot-export |
| UVs (only if textures are introduced) | uv-workflow | materials |
| Generic export questions | export-pipeline | godot-export |
| Delivery to the game | godot-export | qa-review |
| Review / ship check | qa-review | asset-optimization |
| General modeling, bmesh ops, cleanup | blender-modeler | — |

## Typical Chains

```
Prop:       prop-artist → lowpoly-style → materials → asset-optimization → godot-export → qa-review
Building:   environment-artist → prop-artist → materials → asset-optimization → godot-export
Character:  character-archetypes → character-artist → stylized-style → materials → qa-review → godot-export
Creature:   character-archetypes → creature-artist → stylized-style → materials → qa-review → godot-export
Foliage:    vegetation-artist → lowpoly-style → asset-optimization → godot-export
```

## Reference Image Provided

1. Write a short analysis first (`../references/reference-analysis-template.md`): silhouette, proportions,
   palette, key shapes.
2. Match silhouette and proportions before any detail (silhouette render).
3. Then major part breaks, then small details; palette from the reference.
4. Compare loop: render → gap list → fix, at most 3 rounds.
5. Final check with `../references/visual-match-checklist.md`.

## Brief Template

```markdown
**Asset:** <name> — <prop/building/character/creature>, <hero/standard/background>
**Style:** lowpoly stylized fantasy (+ any extra)
**Budget:** <tris> tris, <n> materials (pipeline table)
**Changes:** <what changes vs today, part names kept>
**Skills:** <2–4 skills from the routing table>
```

## Constraints

### MUST DO
- Brief before editing; explicit tri/material budget
- Silhouette before detail; test at gameplay distance
- Keep part/pivot names used by `scripts/` (grep before renaming or merging)
- Build only the asset being worked on; filter Blender output
- Final full-size + silhouette render and TRIS before declaring done

### MUST NOT DO
- Export through the Blender MCP
- Add armatures, textures or UVs unless the user asks
- Add micro-detail before the silhouette reads
- Mix styles without explicit direction
- Exceed the budget "just a little"
