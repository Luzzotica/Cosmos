extends CharacterBody3D
class_name EnemyShipBase
## Shared modular enemy runtime.

const EnemyDataClass: Script = preload("res://scripts/data/enemy_data.gd")
const DamageEventClass: Script = preload("res://scripts/combat/damage_event.gd")
const MovementBehaviorClass: Script = preload("res://scripts/enemies/behaviors/movement_behavior.gd")
const TargetingBehaviorClass: Script = preload("res://scripts/enemies/behaviors/targeting_behavior.gd")
const AttackBehaviorClass: Script = preload("res://scripts/enemies/behaviors/attack_behavior.gd")
const AbilityBehaviorClass: Script = preload("res://scripts/enemies/behaviors/ability_behavior.gd")

signal destroyed
signal target_changed(target: Node3D)

const LASER_DURATION: float = 0.08
const LASER_THICKNESS: float = 0.12

@export var speed: float = 6.0
@export var damage: float = 10.0
@export var attack_range: float = 15.0
@export var attack_cooldown: float = 3.0

var enemy_data: Resource = null
var enemy_id: String = "enemy_standard"
var display_name: String = "Enemy Ship"
var reward_minerals: int = 10

var health_component: HealthComponent
var team_component: TeamComponent
var selectable_component: Node
var is_destroyed: bool = false

var _current_target: Node3D = null
var _fallback_position: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0

var _movement_behavior: RefCounted
var _targeting_behavior: RefCounted
var _attack_behavior: RefCounted
var _ability_behavior: RefCounted
var _last_beam_color: Color = Color(1.0, 0.25, 0.2, 0.95)


func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	_setup_components()
	_init_behaviors()
	_apply_visual_profile()
	_find_target()
	_fallback_position = global_position + Vector3.FORWARD * 8.0


func _physics_process(delta: float) -> void:
	if is_destroyed:
		return

	var tactical_modifier: Dictionary = _get_tactical_modifier()
	var retarget_interval: float = _targeting_behavior.get_retarget_interval(tactical_modifier)
	_retarget_timer -= delta
	var should_retarget: bool = _retarget_timer <= 0.0
	if should_retarget:
		_retarget_timer = retarget_interval
	_update_target_validity()
	if should_retarget and not _should_hold_target():
		_find_target()

	var safe_target: Node3D = _current_target if (_current_target != null and is_instance_valid(_current_target)) else null

	_attack_behavior.tick(delta)
	_ability_behavior.tick(delta, self, safe_target)
	if safe_target != null:
		_attack_behavior.try_attack(self, safe_target, tactical_modifier)

	velocity = _movement_behavior.step(delta, self, safe_target, _fallback_position, tactical_modifier)
	move_and_slide()
	_update_facing(delta)

	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _setup_components() -> void:
	for child in get_children():
		if child is HealthComponent:
			health_component = child
			health_component.destroyed.connect(_on_destroyed)
		elif child is TeamComponent:
			team_component = child


func _init_behaviors() -> void:
	_movement_behavior = MovementBehaviorClass.new()
	_targeting_behavior = TargetingBehaviorClass.new()
	_attack_behavior = AttackBehaviorClass.new()
	_ability_behavior = AbilityBehaviorClass.new()
	_movement_behavior.set_initial_forward(-global_basis.z)
	if enemy_data != null:
		_movement_behavior.configure(enemy_data.movement_profile)
		_targeting_behavior.configure(enemy_data.targeting_profile)
		_attack_behavior.configure(enemy_data.attack_profile)
		_ability_behavior.configure(enemy_data.ability_profile)
		if enemy_data.attack_profile.has("beam_color"):
			_last_beam_color = enemy_data.attack_profile["beam_color"]


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
	if health_component:
		health_component.max_health = data.max_health * health_multiplier
		health_component.health = health_component.max_health
		health_component.set_resistance_profile(data.resistance_multipliers)
	if _movement_behavior:
		_movement_behavior.configure(data.movement_profile)
	if _targeting_behavior:
		_targeting_behavior.configure(data.targeting_profile)
	if _attack_behavior:
		_attack_behavior.configure(data.attack_profile)
	if _ability_behavior:
		_ability_behavior.configure(data.ability_profile)
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


func _find_target() -> void:
	var candidates: Array = _get_player_structures()
	var tactical_modifier: Dictionary = _get_tactical_modifier()
	var selected: Node3D = _targeting_behavior.choose_target(self, candidates, tactical_modifier)
	if selected != _current_target:
		_current_target = selected
		if _current_target != null:
			target_changed.emit(_current_target)


func _update_target_validity() -> void:
	if _current_target == null:
		return
	if not is_instance_valid(_current_target):
		_current_target = null
		return
	if _current_target.get("is_destroyed") == true:
		_current_target = null


func _should_hold_target() -> bool:
	if _current_target == null or not is_instance_valid(_current_target):
		return false
	if _current_target.get("is_destroyed") == true:
		return false
	if enemy_data == null:
		return false
	var targeting: Dictionary = enemy_data.get("targeting_profile")
	if targeting.is_empty():
		return false
	return bool(targeting.get("swarm", false)) or bool(targeting.get("commit_to_target", false))


func _get_player_structures() -> Array:
	var structures: Array = []
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return structures
	var structures_parent: Node = main.get_node_or_null("Structures")
	if not structures_parent:
		return structures
	for child in structures_parent.get_children():
		if child is BaseStructure and not child.is_destroyed:
			structures.append(child)
	return structures


func _get_tactical_modifier() -> Dictionary:
	var manager: Node = get_node_or_null("/root/EnemyManager")
	if manager and manager.has_method("get_tactical_modifier_for_enemy"):
		return manager.call("get_tactical_modifier_for_enemy", self)
	return {}


func spawn_attack_beam(target_pos: Vector3, color: Color) -> void:
	_last_beam_color = color
	var from_pos: Vector3 = global_position + Vector3.UP * 0.6
	var distance: float = from_pos.distance_to(target_pos)
	if distance <= 0.05:
		return
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(LASER_THICKNESS, LASER_THICKNESS, distance)
	beam.mesh = beam_mesh

	var beam_material: StandardMaterial3D = StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = color
	beam_material.emission_enabled = true
	beam_material.emission = color
	beam_material.emission_energy_multiplier = 2.0
	beam_material.no_depth_test = true
	beam.material_override = beam_material
	get_tree().root.add_child(beam)
	beam.global_position = (from_pos + target_pos) * 0.5
	beam.look_at(target_pos, Vector3.UP)
	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(LASER_DURATION)
	cleanup_timer.timeout.connect(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
	)


func _update_facing(delta: float) -> void:
	var planar_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if planar_velocity.length() < 0.1:
		return
	var look_direction: Vector3 = planar_velocity.normalized()
	var target_rotation: float = atan2(look_direction.x, look_direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 4.0)


func _on_destroyed() -> void:
	is_destroyed = true
	destroyed.emit()
	GameState.add_minerals(reward_minerals)
	var manager: Node = get_node_or_null("/root/EnemyManager")
	if manager and manager.has_method("clear_enemy_from_blackboard"):
		manager.call("clear_enemy_from_blackboard", self)
	queue_free()


func set_stats(new_health: float, new_speed: float) -> void:
	if health_component:
		health_component.max_health = new_health
		health_component.health = new_health
	speed = new_speed


func take_damage(amount: float) -> void:
	if health_component:
		health_component.take_damage(amount)


func take_damage_event(event_payload: Dictionary) -> float:
	if health_component == null:
		return 0.0
	return health_component.take_damage_event(event_payload)


func get_selection_name() -> String:
	return display_name


func get_selection_details() -> Dictionary:
	var faction: String = "enemy"
	if team_component:
		faction = team_component.get_team_string()
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
		"stats": [
			{"label": "Damage", "value": "%.0f" % damage},
			{"label": "Speed", "value": "%.1f" % speed}
		]
	}
	if not resistances.is_empty():
		details["stats"].append({"label": "Resists", "value": ", ".join(resistances)})
	if health_component:
		details["health_current"] = health_component.health
		details["health_max"] = health_component.max_health
	return details


func on_deselected() -> void:
	pass
