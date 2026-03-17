@tool
extends Resource
class_name EnemyData
## Data-driven enemy archetype definition.

@export var enemy_id: String = "enemy_standard"
@export var display_name: String = "Enemy Ship"
@export var scene_path: String = "res://scenes/ecs/e_enemy_standard.tscn"

@export_group("Base Stats")
@export var max_health: float = 50.0
@export var speed: float = 6.0
@export var damage: float = 10.0
@export var attack_range: float = 15.0
@export var attack_cooldown: float = 3.0
@export var reward_minerals: int = 10

@export_group("Behavior")
@export var tags: PackedStringArray = PackedStringArray()
@export var movement_profile: Dictionary = {}
@export var targeting_profile: Dictionary = {}
@export var attack_profile: Dictionary = {}
@export var ability_profile: Dictionary = {}

@export_group("Combat")
@export var resistance_multipliers: Dictionary = {}

@export_group("Visuals")
@export var hull_color: Color = Color(0.8, 0.1, 0.1, 1.0)
@export var emission_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var emission_energy: float = 1.5
@export var mesh_scale: Vector3 = Vector3.ONE


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func get_resistance_multiplier(damage_type: String) -> float:
	if resistance_multipliers.has(damage_type):
		return maxf(float(resistance_multipliers[damage_type]), 0.0)
	return 1.0
