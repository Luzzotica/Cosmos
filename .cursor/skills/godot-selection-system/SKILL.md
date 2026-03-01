---
name: godot-selection-system
description: Implements and maintains the project-wide Godot RTS selection system using SelectableComponent Area3D nodes, SelectionManager signal wiring, hover/selection visuals, and selection details UI. Use when adding selectable entities, debugging hover/select behavior, or extending selection panel data.
---

# Godot Selection System

## Purpose

Keep selection behavior consistent across all entity types (player/enemy/neutral) using reusable components and a centralized manager.

## Core Architecture

- `scripts/components/selectable_component.gd`
  - `Area3D` selectable root.
  - Emits selection events and tracks hover/selected state.
- `scripts/components/selection_visuals.gd`
  - Renders hover/selection rings.
- `scripts/autoload/selection_manager.gd`
  - Central selection state.
  - Subscribes to `input_event`, `mouse_entered`, `mouse_exited` for registered selectables.
  - Handles empty-click deselect via `_unhandled_input`.
- `scripts/ui/selection_panel.gd`
  - Consumes normalized selection details and renders entity info.

## Component Scenes

Use reusable scenes, do not hand-build selection node trees:

- `scenes/components/selectable_component.tscn`
- `scenes/components/selection_visuals.tscn`

Each selectable gameplay scene should instance both:

1. `SelectableComponent`
2. `SelectionVisuals`

And set per-entity values like:

- `selection_kind`
- `faction_override` (when needed)
- collider shape/position under `SelectableComponent` child `CollisionShape3D`

## Physics/Input Rules

- Selection layer name in `project.godot`: `3d_physics/layer_2 = "Selection"`.
- `SelectableComponent` config:
  - `input_ray_pickable = true`
  - `collision_layer = 1 << 1`
  - `collision_mask = 0`
- Do not bypass manager with ad-hoc raycast loops unless explicitly requested.
- Keep empty-space deselect behavior in `SelectionManager._unhandled_input`.

## Adding A New Selectable Entity

1. Instance `SelectableComponent` and `SelectionVisuals` scenes in entity `.tscn`.
2. Add/adjust `CollisionShape3D` under `SelectableComponent`.
3. Set `selection_kind` (`structure`, `enemy`, `asteroid`, etc.).
4. Ensure entity provides:
   - `get_selection_name()` (optional but preferred)
   - `get_selection_details() -> Dictionary` (normalized selection payload)
5. Confirm registration path executes (`SelectionManager.register_selectable` from selectable `_ready`).

## Normalized Details Contract

Prefer these keys in `get_selection_details()`:

- identity: `name`, `category`, `faction`
- bars: `health_current`, `health_max`, `resource_current`, `resource_max`
- list rows: `stats` array of `{label, value}`

## Debug Checklist (Selection Broken)

1. Confirm `SelectableComponent` exists in the entity scene tree.
2. Confirm collider exists and is correctly placed under `SelectableComponent`.
3. Confirm manager receives `register_selectable` for entity.
4. Confirm manager receives:
   - `_on_selectable_input_event`
   - `_on_selectable_mouse_entered`
   - `_on_selectable_mouse_exited`
5. Confirm `BuildManager` is not blocking (`is_selection_blocked`, `is_hover_blocked`).
6. Confirm empty-click deselect only triggers on unhandled left click.
