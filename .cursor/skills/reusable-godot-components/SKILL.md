---
name: reusable-godot-components
description: Creates and migrates reusable Godot component scenes (Node/Area3D-based) and updates entity scenes to instance them instead of attaching scripts directly. Use when the user asks to componentize scenes, reuse components across entities, or standardize scene composition in this project.
---

# Reusable Godot Components

## Goal

Turn repeated node+script patterns into reusable component scenes in `scenes/components/`, then instance them from gameplay scenes.

## Apply This Skill When

- User asks to "make this a reusable component."
- User asks to stop duplicating setup across multiple `.tscn` files.
- User asks to convert direct script-attached nodes into instanced component scenes.
- User asks to standardize entity composition (structures/enemies/resources).

## Conventions (Project)

- Put reusable wrappers in `scenes/components/`.
- Keep behavior scripts in `scripts/components/`.
- Instance component scenes from entity scenes; do not duplicate node trees by hand.
- Prefer scene-authored collision/layout over script-generated geometry where possible.
- Keep nested composition explicit (e.g. `PowerNode -> PowerSource -> PowerGenerator`).

## Workflow

1. Identify repeated component patterns across scenes.
2. Create a component scene in `scenes/components/<name>.tscn` with the canonical root node and script.
3. Preserve existing node names unless a rename is explicitly requested.
4. Replace direct script ext_resources in entity scenes with packed scene ext_resources.
5. Swap component nodes to `instance=ExtResource(...)`.
6. Reapply per-entity overrides at the instance level (exported values only).
7. Keep scene hierarchy intact to avoid breaking runtime lookups (`get_node`, sibling traversal).
8. Validate with lint checks on edited files.

## Component Authoring Rules

- Use minimal wrapper scenes:
  - Root node type should match script expectations (`Node3D`, `Area3D`, etc.).
  - Include only required default children (e.g. default `CollisionShape3D` if needed).
- Do not hardcode per-entity values in the component scene when they differ by entity.
- If a component is input-selectable (`Area3D`), keep selection layer/pickable defaults in the component script or base scene.

## Migration Checklist

- [ ] New component scene exists in `scenes/components/`.
- [ ] Entity scene now uses `PackedScene` ext_resource for that component.
- [ ] Old direct script ext_resource removed from entity scene.
- [ ] Overrides (health, team, connection limits, etc.) preserved.
- [ ] Parent/child nesting preserved.
- [ ] Lints pass on all edited files.

## Example Patterns

### Script node -> instanced component scene

- Before: `ext_resource type="Script" path="res://scripts/components/health_component.gd"`
- After: `ext_resource type="PackedScene" path="res://scenes/components/health_component.tscn"`

### Nested power composition

- Keep as separate scenes:
  - `power_node_component.tscn`
  - `power_source_component.tscn`
  - `power_generator_component.tscn`
- Stack them in entity scenes as:
  - `PowerNode` (instance)
  - `PowerSource` under `PowerNode` (instance)
  - `PowerGenerator` under `PowerSource` (instance)
