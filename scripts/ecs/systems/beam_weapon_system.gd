extends System
class_name BeamWeaponSystem
## Batch attack: cooldown, range check, damage application, beam from pool.
## Usable by any entity with C_BeamWeapon (enemies, structures). Excludes C_Destroyed via query.
## Owns a beam pool for reuse; emits C_BeamWeapon.attack_fired for ship visuals.

const BeamPointResolverClass = preload("res://scripts/ecs/beam_point_resolver.gd")
const LASER_DURATION: float = 0.08
const LASER_THICKNESS: float = 0.12
const HEAL_BEAM_THICKNESS: float = 0.06
const HEAL_BEAM_COLOR: Color = Color(0.2, 0.5, 1.0, 0.9)
const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")

var _beam_pool: Array[MeshInstance3D] = []
var _root: Node


func query() -> QueryBuilder:
	return q.with_all([C_BeamWeapon, C_Targeting]).with_any([C_PhysicsBodyRef, C_Structure]).with_none([C_Destroyed])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	if _root == null:
		_root = Engine.get_main_loop().root
	for entity in entities:
		_process_entity_attack(entity, delta)


func play_beam(from_pos: Vector3, target_pos: Vector3, color: Color, duration: float = LASER_DURATION, thickness: float = LASER_THICKNESS) -> void:
	var distance: float = from_pos.distance_to(target_pos)
	if distance <= 0.05:
		return
	var beam: MeshInstance3D = _get_beam_from_pool()
	var beam_mesh: BoxMesh = beam.mesh as BoxMesh
	if beam_mesh == null:
		beam_mesh = BoxMesh.new()
		beam.mesh = beam_mesh
	beam_mesh.size = Vector3(thickness, thickness, distance)
	var mat: StandardMaterial3D = beam.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 2.0
		mat.no_depth_test = true
		beam.material_override = mat
	mat.albedo_color = color
	mat.emission = color
	beam.visible = true
	if _root and not beam.get_parent():
		_root.add_child(beam)
	beam.global_position = (from_pos + target_pos) * 0.5
	beam.look_at(target_pos, Vector3.UP)
	var tree: SceneTree = _root.get_tree() if _root else null
	if tree:
		var timer: SceneTreeTimer = tree.create_timer(duration)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(beam):
				_return_beam_to_pool(beam)
		)


func play_heal_beam(from_pos: Vector3, target_pos: Vector3, duration: float = LASER_DURATION) -> void:
	play_beam(from_pos, target_pos, HEAL_BEAM_COLOR, duration, HEAL_BEAM_THICKNESS)


func _get_beam_from_pool() -> MeshInstance3D:
	if not _beam_pool.is_empty():
		var pooled: MeshInstance3D = _beam_pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.mesh = BoxMesh.new()
	return beam


func _ensure_power(body_node: Node3D) -> void:
	if not body_node.has_method("get_power_user"):
		return
	var power_user: PowerUser = body_node.get_power_user()
	if power_user and not power_user.has_power:
		power_user.draw_power_from_graph()


func _return_beam_to_pool(beam: MeshInstance3D) -> void:
	if not is_instance_valid(beam):
		return
	beam.visible = false
	var parent: Node = beam.get_parent()
	if parent:
		parent.remove_child(beam)
	_beam_pool.append(beam)


func _process_entity_attack(entity: Entity, delta: float) -> void:
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_weapon: C_BeamWeapon = entity.get_component(C_BeamWeapon) as C_BeamWeapon
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades and c_upgrades.is_upgrading:
		return
	var body_node: Node3D = null
	if c_body_ref and c_body_ref.body:
		body_node = c_body_ref.body
	elif c_structure and c_structure.structure_node and is_instance_valid(c_structure.structure_node):
		body_node = c_structure.structure_node
	if body_node == null:
		return
	_ensure_power(body_node)
	c_weapon.cooldown_remaining = maxf(c_weapon.cooldown_remaining - delta, 0.0)
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var attack_range: float = c_weapon.attack_range * float(tactical.get("attack_range_multiplier", 1.0))
	var target: Node3D = _resolve_shoot_target(entity, body_node, c_targeting, c_structure, attack_range)
	if target == null or not is_instance_valid(target):
		return
	if body_node.global_position.distance_to(target.global_position) > attack_range:
		return
	if c_weapon.cooldown_remaining > 0.0:
		return
	# Only consume power right before firing (structures only). Was incorrectly done every frame before.
	if body_node.has_method("consume_power_for_attack") and not body_node.consume_power_for_attack():
		return
	var cooldown: float = c_weapon.attack_cooldown * float(tactical.get("attack_cooldown_multiplier", 1.0))
	c_weapon.cooldown_remaining = maxf(cooldown, 0.1)
	var from_pos: Vector3 = BeamPointResolverClass.get_beam_emit_point(body_node)
	var target_pos: Vector3 = BeamPointResolverClass.get_random_attack_point(target)
	c_weapon.attack_fired.emit(from_pos, target_pos, c_weapon.beam_color)
	play_beam(from_pos, target_pos, c_weapon.beam_color, LASER_DURATION)
	var damage: float = c_weapon.damage * float(tactical.get("damage_multiplier", 1.0))
	var packet: Dictionary = {
		"amount": damage,
		"damage_type": c_weapon.damage_type,
		"source": body_node,
		"tags": PackedStringArray()
	}
	if target.has_method("take_damage_event"):
		target.take_damage_event(packet)
	elif target.has_method("take_damage"):
		target.take_damage(float(packet.amount))


func _resolve_shoot_target(_entity: Entity, body_node: Node3D, c_targeting: C_Targeting, c_structure: C_Structure, attack_range: float) -> Node3D:
	# Structures use their assigned target.
	if c_structure != null:
		return c_targeting.target_node if c_targeting else null
	# Enemies: prioritize main target if in range, else shoot at closest valid target.
	var main_target: Node3D = c_targeting.target_node if c_targeting else null
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_player_structures"):
		return main_target
	var structures: Array = enemy_manager.get_player_structures()
	var in_range: Array[Node3D] = []
	for s in structures:
		var struct: Node3D = s as Node3D
		if struct == null or not is_instance_valid(struct):
			continue
		if struct.get("is_destroyed") == true:
			continue
		var dist: float = body_node.global_position.distance_to(struct.global_position)
		if dist <= attack_range:
			in_range.append(struct)
	if in_range.is_empty():
		return main_target
	# Prioritize main target if it's in range.
	if main_target != null and is_instance_valid(main_target) and main_target in in_range:
		return main_target
	# Use closest in range.
	var closest_dist: float = INF
	var closest: Node3D = null
	for struct in in_range:
		var dist: float = body_node.global_position.distance_to(struct.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = struct
	return closest


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_structure != null:
		return {}
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node
	if body_ref and body_ref.body:
		node_for_lookup = body_ref.body
	else:
		node_for_lookup = entity
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)
