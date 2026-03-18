class_name C_MissileLauncher
extends Component
## ECS data component for missile turret stats and runtime state.
## MissileTurretSystem drives spawning and firing; missiles_stored_changed updates visual rack.

signal missile_fired(from_pos: Vector3, target_pos: Vector3, slot_index: int)
signal missiles_stored_changed(new_count: int)

@export var damage: float = 50.0
@export var attack_range: float = 45.0
@export var aoe_radius: float = 9.0
@export var mineral_cost_per_shot: int = 1
@export var power_cost_per_shot: float = 8.0
@export var damage_type: String = "physical"

@export var missile_capacity: int = 5
@export var missile_spawn_interval: float = 5.0
@export var missile_fire_interval: float = 1.2

var missiles_stored: int = 0
var spawn_timer: float = 0.0
var fire_cooldown_remaining: float = 0.0
