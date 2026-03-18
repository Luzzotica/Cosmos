extends Node3D
class_name MissileBody
## Projectile: launches straight up, then accelerates and slowly turns toward target (ballistic).
## Retargets if target dies, explodes on enemy collision or when no targets.

const BeamPointResolverClass = preload("res://scripts/ecs/beam_point_resolver.gd")
const IMPACT_DISTANCE: float = 0.5
const EXPLOSION_DURATION: float = 0.5
const EXPLOSION_SCALE_END: float = 3.0

const LAUNCH_UP_HEIGHT: float = 0.5
const LAUNCH_ACCEL: float = 35.0
const LAUNCH_INITIAL_SPEED: float = 8.0
const CRUISE_SPEED: float = 22.0
const TURN_RATE: float = 6.0

var target_node: Node3D = null
var damage: float = 25.0
var aoe_radius: float = 9.0
var damage_type: String = "physical"
var source: Node = null
var retarget_range: float = 45.0

var _exploded: bool = false
var _velocity: Vector3 = Vector3.UP * LAUNCH_INITIAL_SPEED
var _launch_height_traveled: float = 0.0
var _phase: int = 0  # 0 = launch up, 1 = ballistic turn
var _last_known_target_pos: Vector3 = Vector3.ZERO


func setup(p_target: Node3D, p_damage: float, p_aoe_radius: float, p_damage_type: String = "physical", p_source: Node = null, p_retarget_range: float = 45.0) -> void:
	target_node = p_target
	damage = p_damage
	aoe_radius = p_aoe_radius
	damage_type = p_damage_type
	source = p_source
	retarget_range = p_retarget_range
	_velocity = Vector3.UP * LAUNCH_INITIAL_SPEED
	_launch_height_traveled = 0.0
	_phase = 0


func _ready() -> void:
	var area: Area3D = _find_collision_area()
	if area:
		area.body_entered.connect(_on_body_entered)


func _find_collision_area() -> Area3D:
	for child in get_children():
		if child is Area3D:
			return child as Area3D
	return null


func _process(delta: float) -> void:
	if _exploded:
		return

	# Update or acquire target
	if target_node != null:
		if not is_instance_valid(target_node):
			target_node = null
		elif _is_target_destroyed(target_node):
			_last_known_target_pos = BeamPointResolverClass.get_random_attack_point(target_node)
			target_node = null
	if target_node == null:
		target_node = _find_closest_enemy_in_range(retarget_range)
		if target_node == null:
			if _last_known_target_pos == Vector3.ZERO:
				_explode(global_position)
				return

	var target_pos: Vector3
	if target_node != null:
		target_pos = BeamPointResolverClass.get_random_attack_point(target_node)
	else:
		target_pos = _last_known_target_pos

	var to_target: Vector3 = target_pos - global_position
	var dist: float = to_target.length()
	if dist <= IMPACT_DISTANCE:
		_explode(global_position)
		return

	if _phase == 0:
		_velocity.y += LAUNCH_ACCEL * delta
		var move: Vector3 = _velocity * delta
		_launch_height_traveled += move.y
		global_position += move
		look_at(global_position + _velocity)
		if _launch_height_traveled >= LAUNCH_UP_HEIGHT:
			_phase = 1
			_velocity = _velocity.normalized() * CRUISE_SPEED
	else:
		var desired_dir: Vector3 = to_target.normalized()
		var current_dir: Vector3 = _velocity.normalized()
		var blended: Vector3 = current_dir.lerp(desired_dir, TURN_RATE * delta).normalized()
		_velocity = blended * CRUISE_SPEED
		global_position += _velocity * delta
		look_at(global_position + _velocity)


func _on_body_entered(body: Node3D) -> void:
	if _exploded:
		return
	if _is_enemy(body):
		_explode(global_position)
	elif _is_asteroid(body) or _is_structure(body):
		pass  # Clip through asteroids and structures


func _is_asteroid(node: Node) -> bool:
	var n: Node = node
	while n:
		var p: Node = n.get_parent()
		if p and p.name == "Asteroids":
			return true
		n = p
	return false


func _is_structure(node: Node) -> bool:
	var n: Node = node
	while n:
		var p: Node = n.get_parent()
		if p and p.name == "Structures":
			return true
		n = p
	return false


func _is_enemy(node: Node) -> bool:
	var n: Node = node
	while n:
		if n is Entity:
			var c_team: C_Team = n.get_component(C_Team) as C_Team
			return c_team != null and c_team.team == "enemy"
		n = n.get_parent()
	return false


func _is_target_destroyed(t: Node) -> bool:
	var n: Node = t
	while n:
		if n is Entity:
			var c_state: C_EnemyState = n.get_component(C_EnemyState) as C_EnemyState
			return c_state != null and c_state.is_destroyed
		n = n.get_parent()
	return false


func _find_closest_enemy_in_range(max_range: float) -> Node3D:
	if ECS == null or ECS.world == null:
		return null
	var enemies: Array = ECS.world.query.with_all([
		{C_EnemyState: {"is_destroyed": {"_eq": false}}},
		{C_Team: {"team": {"_eq": "enemy"}}},
		C_PhysicsBodyRef
	]).execute()
	var closest_dist: float = INF
	var closest: Node3D = null
	for entity in enemies:
		var c_body: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_body == null or c_body.body == null or not is_instance_valid(c_body.body):
			continue
		var dist: float = global_position.distance_to(c_body.body.global_position)
		if dist <= max_range and dist < closest_dist:
			closest_dist = dist
			closest = c_body.body
	return closest


func _explode(pos: Vector3) -> void:
	if _exploded:
		return
	_exploded = true
	if not is_inside_tree():
		queue_free()
		return

	_apply_damage_at(pos)
	_spawn_explosion(pos)
	queue_free()


func _apply_damage_at(pos: Vector3) -> void:
	var world: World3D = get_tree().root.get_world_3d() if is_inside_tree() else null
	if world == null:
		return
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = aoe_radius
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 5
	var area: Area3D = _find_collision_area()
	if area:
		params.exclude = [area.get_rid()]
	var results: Array = space_state.intersect_shape(params, 32)
	var packet: Dictionary = {
		"amount": damage,
		"damage_type": damage_type,
		"source": source,
		"tags": PackedStringArray()
	}
	var seen: Dictionary = {}
	for result in results:
		var collider: Object = result.get("collider", null)
		if collider == null or not (collider is Node):
			continue
		var node: Node = collider as Node
		if not _is_enemy(node):
			continue
		var target: Node = _find_damageable(node)
		if target != null and not seen.get(target.get_instance_id(), false):
			seen[target.get_instance_id()] = true
			if target.has_method("take_damage_event"):
				target.take_damage_event(packet)


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n:
		if n.has_method("take_damage_event"):
			return n
		n = n.get_parent()
	return null


func _spawn_explosion(pos: Vector3) -> void:
	var root: Node = get_tree().root if is_inside_tree() else null
	if root == null:
		return
	var explosion_root: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh.mesh = sphere
	var shader: Shader = load("res://shaders/enemy_energy_crackle.gdshader") as Shader
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("emission_color", Vector3(1.0, 0.4, 0.1))
	mat.set_shader_parameter("emission_energy", 8.0)
	mat.set_shader_parameter("crackle_speed", 8.0)
	mat.set_shader_parameter("crackle_density", 16.0)
	mat.set_shader_parameter("crackle_sharpness", 6.0)
	mat.set_shader_parameter("core_brightness", 0.8)
	mat.set_shader_parameter("pulse_amount", 0.4)
	mat.set_shader_parameter("fresnel_power", 1.8)
	mesh.material_override = mat
	mesh.scale = Vector3(0.2, 0.2, 0.2)
	explosion_root.add_child(mesh)
	root.add_child(explosion_root)
	explosion_root.global_position = pos
	var shrink_duration: float = 0.35
	var tween: Tween = explosion_root.create_tween()
	tween.tween_method(func(t: float) -> void:
		var s: float = lerpf(0.2, EXPLOSION_SCALE_END, t)
		mesh.scale = Vector3(s, s, s)
		mat.set_shader_parameter("emission_energy", lerpf(8.0, 2.0, t))
	, 0.0, 1.0, EXPLOSION_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float) -> void:
		var s: float = lerpf(EXPLOSION_SCALE_END, 0.05, t)
		mesh.scale = Vector3(s, s, s)
		mat.set_shader_parameter("emission_energy", lerpf(2.0, 0.0, t))
	, 0.0, 1.0, shrink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(explosion_root.queue_free)
