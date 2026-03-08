extends System
class_name MiningSystem
## Mining logic: find asteroid, consume power, mine. Replaces MiningStation._process.

var _mining_timers: Dictionary = {}  # entity_id -> timer


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_PowerUser, C_MiningProfile, C_Construction])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_power_user: C_PowerUser = entity.get_component(C_PowerUser) as C_PowerUser
	var c_mining: C_MiningProfile = entity.get_component(C_MiningProfile) as C_MiningProfile
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_structure == null or c_power_user == null or c_mining == null or c_construction == null:
		return
	if c_structure.building_type != "mining_station":
		return
	if not c_construction.is_built:
		return

	var structure_node: Node3D = c_structure.structure_node as Node3D
	if structure_node == null or not is_instance_valid(structure_node):
		return

	# Find target asteroid
	var target_asteroid = null
	if c_mining.target_asteroid_ref and c_mining.target_asteroid_ref.get_ref():
		target_asteroid = c_mining.target_asteroid_ref.get_ref()
	if target_asteroid == null or (target_asteroid.has_method("get") and target_asteroid.get("is_depleted")):
		target_asteroid = _find_nearest_asteroid(structure_node, c_mining.mining_radius)
		c_mining.target_asteroid_ref = null if target_asteroid == null else weakref(target_asteroid)

	if target_asteroid == null:
		return

	# Mining interval
	var eid: int = entity.get_instance_id()
	if not _mining_timers.has(eid):
		_mining_timers[eid] = 0.0
	_mining_timers[eid] += delta
	if _mining_timers[eid] < c_mining.mining_interval:
		return
	_mining_timers[eid] = 0.0

	# Draw power on demand, then consume
	var drawn: float = PowerGraph.draw_power_for_user_entity(entity, c_power_user.use_power_cost)
	if c_power_user.power_buffer < c_power_user.use_power_cost:
		return
	c_power_user.power_buffer -= c_power_user.use_power_cost
	c_power_user.power_consumption = c_power_user.use_power_cost

	if target_asteroid.has_method("mine_minerals"):
		var mined: int = target_asteroid.mine_minerals(int(c_mining.mine_amount))
		if mined > 0 and GameState:
			GameState.add_minerals(mined)
		if structure_node.has_signal("minerals_extracted") and mined > 0:
			structure_node.minerals_extracted.emit(mined)
		if target_asteroid.has_method("get") and target_asteroid.get("is_depleted"):
			c_mining.target_asteroid_ref = null


func _find_nearest_asteroid(from: Node3D, radius: float):
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return null
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if not asteroids_parent:
		return null
	var closest: Node = null
	var closest_dist: float = INF
	for child in asteroids_parent.get_children():
		if child.has_method("mine_minerals") and child.has_method("get_mineral_percentage"):
			if child.get("is_depleted"):
				continue
			var dist: float = from.global_position.distance_to(child.global_position)
			if dist <= radius and dist < closest_dist:
				closest_dist = dist
				closest = child
	return closest
