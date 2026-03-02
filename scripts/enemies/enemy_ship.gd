extends CharacterBody3D
class_name EnemyShip
## Enemy Ship - Attacks player structures with steering behaviors

signal destroyed
signal target_changed(target: Node3D)

const BASE_SPEED: float = 2.0  # Slow enemies (20% of original speed)
const BASE_HEALTH: float = 50.0
const BASE_DAMAGE: float = 10.0
const ATTACK_RANGE: float = 15.0
const ATTACK_COOLDOWN: float = 3.0
const OBSTACLE_AVOIDANCE_RANGE: float = 10.0
const OBSTACLE_AVOIDANCE_FORCE: float = 20.0
const ORBIT_DISTANCE: float = 12.0
const ORBIT_ERROR_RADIUS: float = 3.0
const RETARGET_INTERVAL: float = 0.5
const LASER_DURATION: float = 0.08
const LASER_THICKNESS: float = 0.12

@export var speed: float = BASE_SPEED
@export var damage: float = BASE_DAMAGE

var health_component: HealthComponent
var team_component: TeamComponent

var _current_target: Node3D = null
var _target_position: Vector3 = Vector3.ZERO
var _attack_timer: float = 0.0
var _orbit_direction: int = 0  # +1 for CCW, -1 for CW
var _retarget_timer: float = 0.0
var _steering_force: Vector3 = Vector3.ZERO

var is_destroyed: bool = false
var selectable_component: Node


func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	_setup_components()
	_find_nearest_target()


func _setup_components() -> void:
	for child in get_children():
		if child is HealthComponent:
			health_component = child
			health_component.destroyed.connect(_on_destroyed)
		elif child is TeamComponent:
			team_component = child
	
func _physics_process(delta: float) -> void:
	if is_destroyed:
		return
	
	# Retargeting logic
	_retarget_timer -= delta
	if _retarget_timer <= 0:
		_retarget_timer = RETARGET_INTERVAL
		_find_nearest_target()
	
	# Attack timer
	if _attack_timer > 0:
		_attack_timer -= delta
	
	_update_target()
	
	# Calculate steering forces
	_steering_force = Vector3.ZERO
	
	if _current_target != null:
		var distance_to_target: float = global_position.distance_to(_current_target.global_position)
		if distance_to_target <= ATTACK_RANGE:
			_steering_force += _orbit_steering_force()
			_try_attack()
		else:
			_steering_force += _seek_steering_force(_current_target.global_position)
	else:
		_steering_force += _seek_steering_force(_target_position)
	
	_steering_force += _calculate_obstacle_avoidance()
	
	# Apply steering force as velocity
	velocity = _steering_force.limit_length(speed)
	move_and_slide()
	
	# Rotate to face movement direction
	if velocity.length() > 0.1:
		var look_direction: Vector3 = velocity.normalized()
		look_direction.y = 0
		if look_direction.length() > 0.01:
			var target_rotation: float = atan2(look_direction.x, look_direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
	
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _update_target() -> void:
	if _current_target == null:
		return
	
	# Check if target is destroyed
	if _is_target_destroyed(_current_target):
		_current_target = null
		_find_nearest_target()
		return
	
	_target_position = _current_target.global_position
	
	var distance_to_target: float = global_position.distance_to(_target_position)
	
	if distance_to_target <= ATTACK_RANGE:
		# Set orbit direction if just entering orbit
		if _orbit_direction == 0:
			var to_target: Vector3 = _target_position - global_position
			# Cross product to determine direction
			var cross: float = velocity.x * to_target.z - velocity.z * to_target.x
			_orbit_direction = 1 if cross >= 0 else -1
	else:
		_orbit_direction = 0


func _find_nearest_target() -> void:
	var targets: Array = _get_player_structures()
	
	var closest_distance: float = INF
	var closest_target: Node3D = null
	
	for target in targets:
		if _is_target_destroyed(target):
			continue
		
		var distance: float = global_position.distance_to(target.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = target
	
	if closest_target != _current_target:
		_current_target = closest_target
		if _current_target:
			_target_position = _current_target.global_position
			target_changed.emit(_current_target)


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


func _is_target_destroyed(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return true
	if target.get("is_destroyed") != null:
		return target.is_destroyed
	return false


func _try_attack() -> void:
	if _attack_timer > 0 or _current_target == null:
		return
	
	var distance: float = global_position.distance_to(_current_target.global_position)
	if distance > ATTACK_RANGE:
		return
	
	_attack_timer = ATTACK_COOLDOWN
	_show_laser_beam(global_position + Vector3.UP * 0.6, _current_target.global_position + Vector3.UP * 0.8, Color(1.0, 0.25, 0.2, 0.95))
	
	# Deal damage to target
	if _current_target.has_method("take_damage"):
		_current_target.take_damage(damage)


func _show_laser_beam(from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var distance: float = from_pos.distance_to(to_pos)
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
	beam.global_position = (from_pos + to_pos) * 0.5
	beam.look_at(to_pos, Vector3.UP)

	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(LASER_DURATION)
	cleanup_timer.timeout.connect(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
	)


## Steering force to orbit the target
func _orbit_steering_force() -> Vector3:
	if _current_target == null:
		return Vector3.ZERO
	
	var target_center: Vector3 = _current_target.global_position
	var to_target: Vector3 = target_center - global_position
	var distance: float = to_target.length()
	
	if distance < 0.01:
		return Vector3.ZERO
	
	# Tangential force (perpendicular to radius)
	var tangent: Vector3 = Vector3(-to_target.z, 0, to_target.x).normalized() * _orbit_direction
	var tangent_force: Vector3 = tangent * speed
	
	# Spring force: pull in if too far, push out if too close
	var radius_error: float = distance - ORBIT_DISTANCE
	var spring_force: Vector3 = Vector3.ZERO
	
	if abs(radius_error) > ORBIT_ERROR_RADIUS:
		spring_force = to_target.normalized() * radius_error * 0.5
	
	return tangent_force + spring_force


## Steering force to seek a position
func _seek_steering_force(target: Vector3) -> Vector3:
	var to_target: Vector3 = target - global_position
	to_target.y = 0  # Keep on plane
	
	if to_target.length() < 0.01:
		return Vector3.ZERO
	
	var desired_velocity: Vector3 = to_target.normalized() * speed
	return desired_velocity - velocity


## Obstacle avoidance using simple raycasting
func _calculate_obstacle_avoidance() -> Vector3:
	if velocity.length() < 0.1:
		return Vector3.ZERO
	
	var ray_dir: Vector3 = velocity.normalized()
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + ray_dir * OBSTACLE_AVOIDANCE_RANGE
	)
	query.exclude = [self]
	
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result.is_empty():
		return Vector3.ZERO
	
	var obstacle_pos: Vector3 = result.position
	var distance: float = global_position.distance_to(obstacle_pos)
	
	# Calculate avoidance direction (perpendicular to velocity)
	var avoidance_dir: Vector3 = Vector3(-ray_dir.z, 0, ray_dir.x).normalized()
	
	# Scale force based on proximity
	var strength: float = OBSTACLE_AVOIDANCE_FORCE * (1.0 - distance / OBSTACLE_AVOIDANCE_RANGE)
	
	return avoidance_dir * strength


func _on_destroyed() -> void:
	is_destroyed = true
	destroyed.emit()
	
	# Reward player
	GameState.add_minerals(10)
	
	queue_free()


## Set enemy stats (called by EnemyManager)
func set_stats(new_health: float, new_speed: float) -> void:
	if health_component:
		health_component.max_health = new_health
		health_component.health = new_health
	speed = new_speed


## Take damage
func take_damage(amount: float) -> void:
	if health_component:
		health_component.take_damage(amount)


## Handle mouse input for selection
func _on_input_event(_camera: Node, _event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	pass


func _on_mouse_entered() -> void:
	pass


func _on_mouse_exited() -> void:
	pass


func _on_selection_changed(_entity: Node3D, _entity_type: String) -> void:
	pass


func _on_selection_cleared() -> void:
	pass


func _update_visual_feedback() -> void:
	pass


## Called when this entity is deselected
func on_deselected() -> void:
	pass


func get_selection_name() -> String:
	return "Enemy Ship"


func get_selection_details() -> Dictionary:
	var faction: String = "enemy"
	if team_component:
		faction = team_component.get_team_string()

	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "enemy",
		"faction": faction,
		"damage": damage,
		"speed": speed,
		"weakness": "Laser",
		"stats": [
			{"label": "Damage", "value": "%.0f" % damage},
			{"label": "Speed", "value": "%.1f" % speed},
			{"label": "Weakness", "value": "Laser"}
		]
	}

	if health_component:
		details["health_current"] = health_component.health
		details["health_max"] = health_component.max_health

	return details
