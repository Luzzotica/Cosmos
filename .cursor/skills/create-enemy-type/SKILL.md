---
name: create-enemy-type
description: Creates new ECS enemy types in Cosmos: entity scene, body scene, visual handler, and manager registration. Use when adding a new enemy variant, ship type, or enemy with unique visuals.
---

# Creating a New Enemy Type

## Architecture Overview

Enemies use pure ECS. Each type is a **single self-contained scene**:

- **Root**: Node with `enemy_entity.gd`, `component_resources` baked in
- **ShipBody**: CharacterBody3D child with `enemy_ship_base.gd`, meshes, collision, SelectableComponent, SelectionVisuals
- **VisualHandler** (optional): Node child of ShipBody with `ShipVisualHandler` script for state-driven visuals

Flow: Entity `on_ready` calls `body.initialize_visuals(self)`. Body finds `VisualHandler` child and calls `handler.init(entity)`. Handler fetches components from entity and connects signals. Ship base has NO visual logic.

## 1. Entity Scene (All-in-One)

Create `scenes/ecs/e_enemy_<type>.tscn` with everything inline:

```
Enemy<Type> (Node)
  script = enemy_entity.gd
  component_resources = [C_Health, C_Team, C_Transform3D, C_EnemyState, C_Targeting, C_PhysicsBodyRef, C_CollisionDamage, ...]

  ShipBody (CharacterBody3D, enemy_ship_base.gd)
    Body (Node3D) + Fuselage, ArmL, ArmR (MeshInstance3D)
    CollisionShape3D
    VisualHandler (optional, ShipVisualHandler script)
    SelectableComponent (instance)
    SelectionVisuals (instance)
```

**Required components** (bake in SubResources):

- `C_Health` – current, maximum, resistance_profile
- `C_Team` – team = "enemy"
- `C_Transform3D`, `C_Targeting`, `C_PhysicsBodyRef`, `C_CollisionDamage`
- `C_EnemyState` – speed, display_name, enemy_id, reward_minerals

**Fighter-specific**: `C_FighterMovement`, `C_BeamWeapon` (damage, attack_range, attack_cooldown, beam_color, damage_type), `C_TargetingProfile`  
**Saboteur-specific**: `C_SaboteurState`, `C_SaboteurMovement`, `C_TargetingProfile` (mode = "saboteur_leaf"), plus Barrier node and VisualHandler

Copy an existing scene (e.g. `e_enemy_standard.tscn`, `e_enemy_saboteur.tscn`) and adjust values.

## 2. Enemy Manager Registration

In `scripts/autoload/enemy_manager.gd`, add to `PREFAB_MAP`:

```gdscript
const PREFAB_MAP: Dictionary = {
    # ...
    "enemy_<your_type>": "res://scenes/ecs/e_enemy_<type>.tscn",
}
```

Update `_build_spawn_queue_for_wave` if the new type should appear in waves (e.g. specific slot or wave number condition).

## 3. Visual Handler (When Needed)

If the enemy has state-driven visuals (e.g. saboteur charge/block states):

1. Create `scripts/enemies/<type>_visual_handler.gd` extending `ShipVisualHandler`
2. Override `init(entity: Node)` – get relevant components, connect their signals to internal callbacks
3. Implement `apply_state(state: int, progress: float)` for the actual shader/mesh updates
4. Add a Node named `VisualHandler` as child of ShipBody in the entity scene, with this script

```gdscript
# Example: saboteur_visual_handler.gd
extends ShipVisualHandler
class_name SaboteurVisualHandler

func init(entity: Node) -> void:
    var c_saboteur: C_SaboteurState = entity.get_component(C_SaboteurState) as C_SaboteurState
    if c_saboteur and not c_saboteur.state_changed.is_connected(_on_state_changed):
        c_saboteur.state_changed.connect(_on_state_changed)

func _on_state_changed(new_state: int, progress: float) -> void:
    apply_state(new_state, progress)

func apply_state(new_state: int, progress: float) -> void:
    # Update Body meshes, Barrier visibility, etc.
```

Handler reads Body/Barrier via `get_parent().get_node_or_null("Body")` – parent is the CharacterBody3D.

## 4. Checklist

- [ ] Entity scene is self-contained (no instanced body scenes)
- [ ] ShipBody is a CharacterBody3D child with `enemy_ship_base.gd`, named exactly `ShipBody`
- [ ] All required components baked in component_resources
- [ ] `PREFAB_MAP` includes the new enemy_id
- [ ] Wave composition or spawn logic updated if needed
- [ ] VisualHandler added only when custom visuals required; handler wires entity components in `init()`
