extends CharacterBody3D
class_name EnemyShipBase
## Shared modular enemy runtime. Used as physics body child of ECS entity.
## ECS systems drive movement, targeting, and attack; this node holds visuals and collision.

const EnemyDataClass: Script = preload("res://scripts/data/enemy_data.gd")

signal destroyed
signal target_changed(target: Node3D)

@export var speed: float = 6.0
@export var damage: float = 10.0
@export var attack_range: float = 15.0
@export var attack_cooldown: float = 3.0

var enemy_data: Resource = null
var enemy_id: String = "enemy_standard"
var display_name: String = "Enemy Ship"
var reward_minerals: int = 10

var selectable_component: Node
var is_destroyed: bool = false


func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	_apply_visual_profile()


func _physics_process(_delta: float) -> void:
	if is_destroyed:
		return
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func set_enemy_data(data: Resource, health_multiplier: float = 1.0, speed_multiplier: float = 1.0) -> void:
	enemy_data = data
	if data == null:
		return
	enemy_id = data.enemy_id
	display_name = data.display_name
	reward_minerals = data.reward_minerals
	speed = data.speed * speed_multiplier
	damage = data.damage
	attack_range = data.attack_range
	attack_cooldown = data.attack_cooldown
	_apply_visual_profile()


func _apply_visual_profile() -> void:
	if enemy_data == null:
		return
	var body: Node = get_node_or_null("Body")
	if body == null:
		return
	body.scale = enemy_data.mesh_scale
	for child in body.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_inst: MeshInstance3D = child as MeshInstance3D
		var mat: Material = mesh_inst.get_active_material(0)
		if mat == null:
			continue
		var cloned: Material = mat.duplicate()
		if cloned is ShaderMaterial:
			var shader_mat: ShaderMaterial = cloned as ShaderMaterial
			shader_mat.set_shader_parameter("emission_color", enemy_data.emission_color)
			shader_mat.set_shader_parameter("emission_energy", enemy_data.emission_energy)
		elif cloned is StandardMaterial3D:
			var std_mat: StandardMaterial3D = cloned as StandardMaterial3D
			std_mat.albedo_color = enemy_data.hull_color
			std_mat.emission_enabled = true
			std_mat.emission = enemy_data.emission_color
			std_mat.emission_energy_multiplier = enemy_data.emission_energy
		mesh_inst.set_surface_override_material(0, cloned)


func set_stats(new_health: float, new_speed: float) -> void:
	# ECS sets health at spawn; speed is stored in C_EnemyState
	speed = new_speed


func take_damage(amount: float) -> void:
	var entity: Node = get_parent()
	if entity and entity.has_method("get_component"):
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		if c_health:
			c_health.current = maxf(0.0, c_health.current - amount)


func take_damage_event(event_payload: Dictionary) -> float:
	var entity: Node = get_parent()
	if entity == null or not entity.has_method("get_component"):
		return 0.0
	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	if c_health == null:
		return 0.0
	var amount: float = float(event_payload.get("amount", 0.0))
	var dmg_type: String = String(event_payload.get("damage_type", "generic"))
	var multiplier: float = c_health.resistance_profile.get(dmg_type, 1.0) if c_health.resistance_profile else 1.0
	var actual: float = amount * multiplier
	c_health.current = maxf(0.0, c_health.current - actual)
	return actual


func get_selection_name() -> String:
	return display_name


func get_selection_details() -> Dictionary:
	var entity: Node = get_parent()
	var faction: String = "enemy"
	var health_cur: float = 0.0
	var health_max: float = 0.0
	if entity and entity.has_method("get_component"):
		var c_team: C_Team = entity.get_component(C_Team) as C_Team
		if c_team:
			faction = c_team.team
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		if c_health:
			health_cur = c_health.current
			health_max = c_health.maximum

	var resistances: Array[String] = []
	if enemy_data:
		for damage_type in enemy_data.resistance_multipliers.keys():
			var mult: float = float(enemy_data.resistance_multipliers[damage_type])
			if mult <= 0.0:
				resistances.append("%s Immune" % String(damage_type).capitalize())
			elif mult < 1.0:
				var reduced_pct: int = int(round((1.0 - mult) * 100.0))
				resistances.append("%s -%d%%" % [String(damage_type).capitalize(), reduced_pct])

	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "enemy",
		"faction": faction,
		"damage": damage,
		"speed": speed,
		"health_current": health_cur,
		"health_max": health_max,
		"stats": [
			{"label": "Damage", "value": "%.0f" % damage},
			{"label": "Speed", "value": "%.1f" % speed}
		]
	}
	if not resistances.is_empty():
		details["stats"].append({"label": "Resists", "value": ", ".join(resistances)})
	return details


func on_deselected() -> void:
	pass
