extends System
class_name LaserTurretTargetingSystem
## Batch targeting: finds closest enemy in range for each laser turret.

var _enemies_cache: Array[Node3D] = []
var _cache_valid: bool = false


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_TurretProfile, C_Targeting, C_Construction])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	_refresh_enemies_cache()
	if entities.is_empty():
		return
	for entity in entities:
		_process_entity_targeting(entity)


func _refresh_enemies_cache() -> void:
	_enemies_cache.clear()
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if not enemies_parent:
		return
	for child in enemies_parent.get_children():
		var targetable: Node3D = _get_enemy_targetable(child)
		if targetable != null and not _is_target_destroyed(targetable):
			_enemies_cache.append(targetable)


func _get_enemy_targetable(node: Node) -> Node3D:
	if node is CharacterBody3D:
		return node as Node3D
	for c in node.get_children():
		if c is CharacterBody3D:
			return c as Node3D
	return node as Node3D if node is Node3D else null


func _is_target_destroyed(t: Node3D) -> bool:
	if t.has_method("is_destroyed"):
		return t.is_destroyed
	if t.get("is_destroyed") != null:
		return t.is_destroyed
	return false


func _process_entity_targeting(entity: Entity) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_turret: C_TurretProfile = entity.get_component(C_TurretProfile) as C_TurretProfile
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_structure == null or c_turret == null or c_targeting == null:
		return
	if c_structure.building_type != "laser_turret":
		return
	if c_structure.is_destroyed:
		return
	var structure: Node3D = c_structure.structure_node
	if structure == null or not is_instance_valid(structure):
		return
	var is_built: bool = structure.is_built()
	var has_power: bool = structure.has_operational_power()
	if not is_built:
		return
	# Only target when powered
	if not has_power:
		if c_targeting.target_node != null:
			c_targeting.target_node = null
			if structure.has_signal("target_lost"):
				structure.target_lost.emit()
		return

	# Validate current target
	if c_targeting.target_node != null:
		var lost: bool = false
		if not is_instance_valid(c_targeting.target_node):
			lost = true
		elif _is_target_destroyed(c_targeting.target_node):
			lost = true
		elif structure.global_position.distance_to(c_targeting.target_node.global_position) > c_turret.attack_range:
			lost = true
		if lost:
			c_targeting.target_node = null
			if structure.has_signal("target_lost"):
				structure.target_lost.emit()

	# Find new target if needed
	if c_targeting.target_node == null:
		var closest: Node3D = null
		var closest_dist: float = INF
		for enemy in _enemies_cache:
			var dist: float = structure.global_position.distance_to(enemy.global_position)
			if dist <= c_turret.attack_range and dist < closest_dist:
				closest_dist = dist
				closest = enemy
		if closest != null and structure.has_signal("target_acquired"):
			structure.target_acquired.emit(closest)
		c_targeting.target_node = closest
