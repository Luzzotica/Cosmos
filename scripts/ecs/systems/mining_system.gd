extends System
class_name MiningSystem
## Queries mining stations and nearby asteroids via ECS. Handles target acquisition,
## mining timer ticks, mineral extraction, and delegates visuals to the MiningStation node.

const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")

var _asteroid_cache: Array[Entity] = []
var _asteroid_cache_timer: float = 0.0
const ASTEROID_CACHE_INTERVAL: float = 0.5


func query() -> QueryBuilder:
	return q.with_all([C_MiningStation, C_Structure, C_Transform3D]).with_none([C_Construction])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	_asteroid_cache_timer += delta
	if _asteroid_cache_timer >= ASTEROID_CACHE_INTERVAL:
		_asteroid_cache_timer = 0.0
		_refresh_asteroid_cache()
	for entity in entities:
		_process_mining_entity(entity, delta)


func _refresh_asteroid_cache() -> void:
	_asteroid_cache.clear()
	_collect_asteroids_from_scene_tree()


func _collect_asteroids_from_scene_tree() -> void:
	var main: Node = ECS.world.get_parent() if ECS and ECS.world else null
	if not main:
		return
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if not asteroids_parent:
		return
	for child in asteroids_parent.get_children():
		if not (child is Entity) or not is_instance_valid(child):
			continue
		var ca: C_Asteroid = child.get_component(C_Asteroid) as C_Asteroid
		var ct: C_Transform3D = child.get_component(C_Transform3D) as C_Transform3D
		if ca and ct:
			_asteroid_cache.append(child)


func _process_mining_entity(entity: Entity, delta: float) -> void:
	var c_mining: C_MiningStation = entity.get_component(C_MiningStation) as C_MiningStation
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	if c_mining == null or c_structure == null or c_transform == null:
		return
	if c_structure.is_destroyed:
		return
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades and c_upgrades.is_upgrading:
		c_mining.is_mining = false
		return

	var station: Node3D = c_structure.structure_node
	if station == null or not is_instance_valid(station):
		return
	if not station.has_method("is_built") or not station.call("is_built"):
		return

	var station_pos: Vector3 = station.global_position
	if c_mining.target_entity == null or not is_instance_valid(c_mining.target_entity):
		c_mining.target_entity = null
		_find_nearest_asteroid(c_mining, station_pos)
	else:
		var target_asteroid: C_Asteroid = c_mining.target_entity.get_component(C_Asteroid) as C_Asteroid
		if target_asteroid == null or target_asteroid.is_depleted:
			c_mining.target_entity = null
			_find_nearest_asteroid(c_mining, station_pos)

	if c_mining.target_entity == null:
		c_mining.is_mining = false
		return

	_ensure_power(station)

	c_mining.mining_timer += delta
	if c_mining.mining_timer >= c_mining.mining_interval:
		c_mining.mining_timer = 0.0
		_try_mine(c_mining, station)


func _find_nearest_asteroid(c_mining: C_MiningStation, station_pos: Vector3) -> void:
	var best_entity: Entity = null
	var best_dist: float = INF

	for asteroid_entity in _asteroid_cache:
		if not is_instance_valid(asteroid_entity):
			continue
		var c_asteroid: C_Asteroid = asteroid_entity.get_component(C_Asteroid) as C_Asteroid
		if c_asteroid == null or c_asteroid.is_depleted:
			continue
		var c_ast_transform: C_Transform3D = asteroid_entity.get_component(C_Transform3D) as C_Transform3D
		if c_ast_transform == null:
			continue
		var ast_pos: Vector3 = c_ast_transform.position
		if "global_position" in asteroid_entity:
			ast_pos = asteroid_entity.global_position
		var dist: float = station_pos.distance_to(ast_pos)
		if dist <= c_mining.mining_radius and dist < best_dist:
			best_dist = dist
			best_entity = asteroid_entity

	if best_entity != c_mining.target_entity:
		c_mining.target_entity = best_entity


func _ensure_power(station: Node3D) -> void:
	if not station.has_method("get_power_user"):
		return
	var power_user: PowerUser = station.get_power_user()
	if power_user and not power_user.has_power:
		power_user.draw_power_from_graph()


func _try_mine(c_mining: C_MiningStation, station: Node3D) -> void:
	var power_user: PowerUser = station.get_power_user() if station.has_method("get_power_user") else null
	if power_user == null:
		c_mining.is_mining = false
		return

	if not power_user.consume_power():
		c_mining.is_mining = false
		return

	var target: Entity = c_mining.target_entity
	if target == null or not is_instance_valid(target):
		c_mining.is_mining = false
		return

	var c_asteroid: C_Asteroid = target.get_component(C_Asteroid) as C_Asteroid
	if c_asteroid == null or c_asteroid.is_depleted:
		c_mining.is_mining = false
		c_mining.target_entity = null
		return

	c_mining.is_mining = true
	var mined: int = 0
	if target.has_method("mine_minerals"):
		mined = target.call("mine_minerals", int(c_mining.mine_amount))
	if mined > 0:
		GameState.add_minerals_from_mining(mined)
		if station.has_method("fire_mining_beam"):
			station.call("fire_mining_beam")
		if target.has_method("show_mining_impact"):
			target.call("show_mining_impact")

		if c_asteroid.is_depleted:
			c_mining.target_entity = null
