extends Node3D
## Debug overlay: draws spheres at each enemy's target move point.
const ObstacleDebugStoreClass = preload("res://scripts/debug/obstacle_debug_store.gd")
## Enable in the inspector to visualize where enemies are trying to fly toward.
## Helps tune movement math (e.g. min_safe_distance, target_offset_length).

@export var enabled: bool = false
@export var sphere_radius: float = 0.6
@export var fighter_color: Color = Color(1.0, 0.3, 0.3, 0.85)
@export var saboteur_color: Color = Color(0.3, 0.8, 1.0, 0.85)
## When enabled, draw obstacle avoidance lookup spheres and heading arrows.
@export var obstacle_debug_enabled: bool = true

var _sphere_pool: Array[MeshInstance3D] = []
var _obstacle_sphere_pool: Array[MeshInstance3D] = []
var _obstacle_arrow_pool: Array[MeshInstance3D] = []
var _shared_sphere_mesh: SphereMesh
var _fighter_material: StandardMaterial3D
var _saboteur_material: StandardMaterial3D
var _obstacle_sphere_material: StandardMaterial3D
var _obstacle_arrow_material: StandardMaterial3D


func _ready() -> void:
	visible = false
	_shared_sphere_mesh = SphereMesh.new()
	_shared_sphere_mesh.radius = sphere_radius
	_shared_sphere_mesh.height = sphere_radius * 2.0
	_create_materials()
	_create_obstacle_debug_materials()


func _process(_delta: float) -> void:
	if not enabled or not ECS or not ECS.world:
		visible = false
		return

	var target_positions: Array[Dictionary] = []  # { position: Vector3, is_saboteur: bool }
	_collect_target_positions(target_positions)

	_ensure_pool_size(target_positions.size())
	for i in target_positions.size():
		var entry: Dictionary = target_positions[i]
		var sphere: MeshInstance3D = _sphere_pool[i]
		sphere.global_position = Vector3(entry.position.x, 0.5, entry.position.z)
		sphere.material_override = _saboteur_material if entry.get("is_saboteur", false) else _fighter_material
		sphere.visible = true

	for i in range(target_positions.size(), _sphere_pool.size()):
		_sphere_pool[i].visible = false

	var has_obstacle_debug: bool = false
	if obstacle_debug_enabled:
		var obstacle_entries: Array[Dictionary] = ObstacleDebugStoreClass.pop_all()
		_ensure_obstacle_pool_size(obstacle_entries.size())
		for i in obstacle_entries.size():
			var entry: Dictionary = obstacle_entries[i]
			_draw_obstacle_entry(i, entry)
		for i in range(obstacle_entries.size(), _obstacle_sphere_pool.size()):
			_obstacle_sphere_pool[i].visible = false
			_obstacle_arrow_pool[i].visible = false
		has_obstacle_debug = not obstacle_entries.is_empty()

	visible = not target_positions.is_empty() or has_obstacle_debug


func _create_materials() -> void:
	_fighter_material = StandardMaterial3D.new()
	_fighter_material.albedo_color = fighter_color
	_fighter_material.emission_enabled = true
	_fighter_material.emission = fighter_color
	_fighter_material.emission_energy_multiplier = 2.5
	_fighter_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fighter_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_saboteur_material = StandardMaterial3D.new()
	_saboteur_material.albedo_color = saboteur_color
	_saboteur_material.emission_enabled = true
	_saboteur_material.emission = saboteur_color
	_saboteur_material.emission_energy_multiplier = 2.5
	_saboteur_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_saboteur_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _create_obstacle_debug_materials() -> void:
	_obstacle_sphere_material = StandardMaterial3D.new()
	_obstacle_sphere_material.albedo_color = Color(0.2, 0.9, 0.5, 0.25)
	_obstacle_sphere_material.emission_enabled = true
	_obstacle_sphere_material.emission = Color(0.2, 0.9, 0.5, 0.5)
	_obstacle_sphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_obstacle_sphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_obstacle_arrow_material = StandardMaterial3D.new()
	_obstacle_arrow_material.albedo_color = Color(1.0, 0.9, 0.2, 0.9)
	_obstacle_arrow_material.emission_enabled = true
	_obstacle_arrow_material.emission = Color(1.0, 0.9, 0.2, 1.0)
	_obstacle_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_obstacle_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _ensure_obstacle_pool_size(count: int) -> void:
	while _obstacle_sphere_pool.size() < count:
		var sphere: MeshInstance3D = MeshInstance3D.new()
		sphere.mesh = SphereMesh.new()
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sphere.material_override = _obstacle_sphere_material
		add_child(sphere)
		_obstacle_sphere_pool.append(sphere)
		var arrow: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.12, 0.12, 4.0)
		arrow.mesh = box
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arrow.material_override = _obstacle_arrow_material
		add_child(arrow)
		_obstacle_arrow_pool.append(arrow)


func _draw_obstacle_entry(index: int, entry: Dictionary) -> void:
	var pos: Vector3 = entry.get("position", Vector3.ZERO)
	var sphere_center: Vector3 = entry.get("sphere_center", pos)
	var radius: float = entry.get("sphere_radius", 1.0)
	var desired_dir: Vector3 = entry.get("desired_dir", Vector3.FORWARD)
	if desired_dir.length_squared() < 0.0001:
		desired_dir = Vector3.FORWARD
	desired_dir = desired_dir.normalized()

	var sphere_mi: MeshInstance3D = _obstacle_sphere_pool[index]
	sphere_mi.global_position = Vector3(sphere_center.x, 0.5, sphere_center.z)
	var sphere_mesh: SphereMesh = sphere_mi.mesh as SphereMesh
	if sphere_mesh:
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2.0
	sphere_mi.visible = true

	var arrow_mi: MeshInstance3D = _obstacle_arrow_pool[index]
	var arrow_len: float = 4.0
	var arrow_center: Vector3 = pos + desired_dir * (arrow_len * 0.5)
	arrow_center.y = 0.5
	arrow_mi.global_position = arrow_center
	arrow_mi.look_at(arrow_center + desired_dir * arrow_len, Vector3.UP)
	arrow_mi.visible = true


func _ensure_pool_size(count: int) -> void:
	while _sphere_pool.size() < count:
		var sphere: MeshInstance3D = MeshInstance3D.new()
		sphere.mesh = _shared_sphere_mesh
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sphere)
		_sphere_pool.append(sphere)


func _collect_target_positions(out: Array[Dictionary]) -> void:
	# Fighters: C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, C_FighterMovement
	# Saboteurs (MOVE_TO only): C_SaboteurState, C_SaboteurMovement, C_Targeting, etc.
	var fighters = ECS.world.query.with_all([C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, C_FighterMovement]).execute()
	for entity in fighters:
		var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
		var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
		var c_fighter: C_FighterMovement = entity.get_component(C_FighterMovement) as C_FighterMovement
		var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_state == null or c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
			continue
		var body: CharacterBody3D = c_body_ref.body
		var target_pos: Vector3 = _get_fighter_target_position(body, c_targeting, c_fighter)
		out.append({"position": target_pos, "is_saboteur": false})

	var saboteurs = ECS.world.query.with_all([C_SaboteurState, C_SaboteurMovement, C_Targeting, C_Transform3D, C_PhysicsBodyRef, C_EnemyState]).execute()
	for entity in saboteurs:
		var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
		var c_saboteur: C_SaboteurState = entity.get_component(C_SaboteurState) as C_SaboteurState
		var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
		var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_state == null or c_state.is_destroyed or c_saboteur == null or c_body_ref == null or c_body_ref.body == null:
			continue
		if c_saboteur.state != C_SaboteurState.State.MOVE_TO:
			continue
		var body: CharacterBody3D = c_body_ref.body
		var target_pos: Vector3 = _get_saboteur_target_position(body, c_targeting)
		out.append({"position": target_pos, "is_saboteur": true})


func _get_fighter_target_position(body: CharacterBody3D, c_targeting: C_Targeting, c_fighter: C_FighterMovement) -> Vector3:
	if c_targeting == null:
		return body.global_position + Vector3.FORWARD * 8.0
	if c_targeting.target_node != null and is_instance_valid(c_targeting.target_node):
		var target_pos: Vector3 = (c_targeting.target_node as Node3D).global_position
		var ship_pos: Vector3 = body.global_position
		var to_struct: Vector3 = target_pos - ship_pos
		to_struct.y = 0.0
		if to_struct.length() > 0.01:
			var perp: Vector3 = Vector3(-to_struct.z, 0.0, to_struct.x).normalized()
			perp *= signf(c_fighter.target_offset_side) if c_fighter.target_offset_side != 0.0 else 1.0
			target_pos += perp * c_fighter.target_offset_length
		return target_pos
	if c_targeting.fallback_position.length_squared() > 0.01:
		return c_targeting.fallback_position
	return body.global_position + Vector3.FORWARD * 8.0


func _get_saboteur_target_position(body: CharacterBody3D, c_targeting: C_Targeting) -> Vector3:
	if c_targeting == null:
		return body.global_position + Vector3.FORWARD * 8.0
	if c_targeting.target_position.x != INF and c_targeting.target_position.x != -INF:
		return c_targeting.target_position
	if c_targeting.target_node != null and is_instance_valid(c_targeting.target_node):
		return (c_targeting.target_node as Node3D).global_position
	if c_targeting.fallback_position.length_squared() > 0.01:
		return c_targeting.fallback_position
	return body.global_position + Vector3.FORWARD * 8.0
