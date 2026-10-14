extends Node
## MapLoader - Handles loading and instantiating maps from MapData resources

const MapValidatorClass: Script = preload("res://scripts/data/map_validator.gd")
const C_VictoryMonolithClass = preload("res://scripts/ecs/components/c_victory_monolith.gd")

## Same bitmask as ObstacleBody on structures and asteroids (see scenes/ecs/e_*.tscn).
const OBSTACLE_COLLISION_MASK: int = 524292
const ASTEROID_PLACEMENT_MARGIN: float = 0.4
const MAX_ASTEROID_CLOUD_PLACEMENT_ATTEMPTS: int = 48

signal map_loaded(map_data: MapData)
signal map_cleared
signal map_load_failed(errors: PackedStringArray)

var current_map: MapData = null

# Scene references
var asteroid_scene: PackedScene
var _cloud_marker_scene: PackedScene


func _ready() -> void:
	_load_scenes()


func _load_scenes() -> void:
	asteroid_scene = load("res://scenes/ecs/e_asteroid.tscn")
	_cloud_marker_scene = load("res://scenes/editor/cloud_marker.tscn")


func _get_structure_scene(building_type: String) -> PackedScene:
	## Uses BuildManager's BuildingData as single source of truth for structure scenes.
	if BuildManager:
		var data: Resource = BuildManager.get_building_data(building_type)
		if data and data.get("scene") is PackedScene:
			return data.scene
	return null


## Load a map from a MapData resource.
## When for_editor is true, asteroid clouds are spawned as CloudMarker nodes instead of expanded asteroids.
func load_map(map_data: MapData, for_editor: bool = false) -> void:
	if not map_data:
		push_error("Cannot load null map data")
		return

	var validation: Dictionary = MapValidatorClass.validate_map_data(map_data)
	if not bool(validation.get("is_valid", false)):
		var errors: PackedStringArray = validation.get("errors", PackedStringArray())
		for err in errors:
			push_error("Map validation failed: %s" % err)
		map_load_failed.emit(errors)
		return
	
	clear_current_map()
	current_map = map_data
	
	var root: Node = get_tree().root
	var main: Node = root.get_node_or_null("Main")
	if not main:
		push_error("Main scene not found")
		return
	
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	var structures_parent: Node = main.get_node_or_null("Structures")
	_load_map_into(structures_parent, asteroids_parent, map_data, true, for_editor)
	map_loaded.emit(map_data)


## Load map into custom containers (e.g. main menu preview). Skips GameState/EnemyManager.
func load_map_into_containers(map_data: MapData, structures_parent: Node3D, asteroids_parent: Node3D, apply_game_state: bool = false, for_editor: bool = false) -> void:
	if not map_data:
		push_error("Cannot load null map data")
		return

	var validation: Dictionary = MapValidatorClass.validate_map_data(map_data)
	if not bool(validation.get("is_valid", false)):
		var errors: PackedStringArray = validation.get("errors", PackedStringArray())
		for err in errors:
			push_error("Map validation failed: %s" % err)
		map_load_failed.emit(errors)
		return

	_load_map_into(structures_parent, asteroids_parent, map_data, apply_game_state, for_editor)
	map_loaded.emit(map_data)


func _load_map_into(structures_parent: Node3D, asteroids_parent: Node3D, map_data: MapData, apply_game_state: bool, for_editor: bool = false) -> void:
	# Structures first so asteroid placement queries can collide against ObstacleBody.
	if structures_parent:
		for structure_data in map_data.starting_structures:
			_spawn_structure(structures_parent, structure_data)

	var space_state: PhysicsDirectSpaceState3D = null
	if asteroids_parent and asteroids_parent.is_inside_tree():
		var world: World3D = asteroids_parent.get_world_3d()
		if world:
			space_state = world.direct_space_state

	if asteroids_parent:
		for asteroid_data in map_data.asteroids:
			_spawn_asteroid(asteroids_parent, asteroid_data, space_state)
		for cloud_data in map_data.asteroid_clouds:
			if for_editor and _cloud_marker_scene:
				_spawn_cloud_marker(asteroids_parent, cloud_data)
			else:
				_spawn_asteroid_cloud(asteroids_parent, cloud_data, space_state)

	if apply_game_state:
		current_map = map_data
		GameState.apply_map_settings(map_data)
		if EnemyManager and EnemyManager.has_method("apply_map_wave_settings"):
			EnemyManager.apply_map_wave_settings(map_data)


## Load a map from a JSON file.
## When for_editor is true, asteroid clouds are spawned as CloudMarker nodes.
func load_map_from_json(path: String, for_editor: bool = false) -> void:
	var map_data: MapData = MapData.load_from_json(path)
	if map_data:
		load_map(map_data, for_editor)


## Load map from dictionary data (used by online map payloads)
func load_map_from_dict(data: Dictionary) -> void:
	var strict_check: Dictionary = MapValidatorClass.validate_json_dict(data)
	if not bool(strict_check.get("is_valid", false)):
		var schema_errors: PackedStringArray = strict_check.get("errors", PackedStringArray())
		for schema_err in schema_errors:
			push_error("Map schema failed: %s" % schema_err)
		map_load_failed.emit(schema_errors)
		return
	var map_data: MapData = MapData._create_from_dict(data)
	load_map(map_data)


## Clear the current map
func clear_current_map() -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	# Clear asteroids
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if asteroids_parent:
		for child in asteroids_parent.get_children():
			if ECS and ECS.world and child is Entity:
				ECS.world.remove_entity(child as Entity)
			else:
				child.queue_free()
	
	# Clear structures
	var structures_parent: Node = main.get_node_or_null("Structures")
	if structures_parent:
		for child in structures_parent.get_children():
			child.queue_free()
	
	# Clear enemies
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if enemies_parent:
		for child in enemies_parent.get_children():
			child.queue_free()
	
	# Clear repair robots and projectiles (remove from ECS first, then free)
	var repair_robots_parent: Node = main.get_node_or_null("RepairRobots")
	if repair_robots_parent:
		for child in repair_robots_parent.get_children():
			if ECS and ECS.world and child is Entity:
				ECS.world.remove_entity(child as Entity)
			child.queue_free()
	var projectiles_parent: Node = main.get_node_or_null("Projectiles")
	if projectiles_parent:
		for child in projectiles_parent.get_children():
			if ECS and ECS.world and child is Entity:
				ECS.world.remove_entity(child as Entity)
			child.queue_free()
	
	current_map = null
	map_cleared.emit()


func _asteroid_probe_radius_for_size(size: float) -> float:
	return maxf(size * 0.5 + ASTEROID_PLACEMENT_MARGIN, 0.75)


func _is_asteroid_spawn_clear(space_state: PhysicsDirectSpaceState3D, world_pos: Vector3, size: float) -> bool:
	if space_state == null:
		return true
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = _asteroid_probe_radius_for_size(size)
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), world_pos)
	params.collision_mask = OBSTACLE_COLLISION_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var results: Array = space_state.intersect_shape(params, 32)
	return results.is_empty()


## Spawn an asteroid from placement data. When [param space_state] is set, skips spawn if overlapping obstacle bodies.
func _spawn_asteroid(parent: Node3D, data: AsteroidPlacement, space_state: PhysicsDirectSpaceState3D = null) -> void:
	if not asteroid_scene:
		return
	if space_state != null and not _is_asteroid_spawn_clear(space_state, data.position, data.size):
		push_warning("Asteroid placement overlaps obstacles at %s; skipped." % str(data.position))
		return

	var entity: Node = asteroid_scene.instantiate() as Node
	if entity:
		parent.add_child(entity)
		var body: Node3D = entity.get_node_or_null("AsteroidBody") as Node3D
		if body:
			body.global_position = data.position
		if ECS and ECS.world:
			ECS.world.add_entity(entity, [], false)
		if entity.has_method("set_size"):
			entity.call("set_size", data.size)
		if entity.has_method("set_minerals"):
			entity.call("set_minerals", data.minerals)


## Spawn a CloudMarker in editor mode (cloud region representation, no asteroids)
func _spawn_cloud_marker(parent: Node3D, data: Resource) -> void:
	if not _cloud_marker_scene:
		return
	var marker: Node3D = _cloud_marker_scene.instantiate() as Node3D
	if marker:
		parent.add_child(marker)
		marker.global_position = data.center
		if marker.get("cloud_data") != null:
			marker.set("cloud_data", data)


## Spawn a deterministic asteroid cloud from placement data
func _spawn_asteroid_cloud(parent: Node3D, data: Resource, space_state: PhysicsDirectSpaceState3D = null) -> void:
	if data.count <= 0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if data.seed != 0:
		rng.seed = data.seed
	elif current_map and current_map.procedural_seed != 0:
		rng.seed = current_map.procedural_seed
	else:
		rng.randomize()

	for _i in range(data.count):
		var placement: AsteroidPlacement = AsteroidPlacement.new()
		var placed: bool = false
		for _attempt in range(MAX_ASTEROID_CLOUD_PLACEMENT_ATTEMPTS):
			var angle: float = rng.randf_range(0.0, TAU)
			var dist: float = rng.randf_range(0.0, data.radius)
			var spawn_pos: Vector3 = data.center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			placement.position = spawn_pos
			placement.size = rng.randf_range(data.min_size, data.max_size)
			placement.minerals = rng.randf_range(data.min_minerals, data.max_minerals)
			if space_state == null or _is_asteroid_spawn_clear(space_state, placement.position, placement.size):
				_spawn_asteroid(parent, placement, null)
				placed = true
				break
		if not placed:
			push_warning(
				"Asteroid cloud could not place a rock after %d attempts (center %s); skipped one." % [
					MAX_ASTEROID_CLOUD_PLACEMENT_ATTEMPTS,
					str(data.center)
				]
			)


func spawn_asteroid_for_editor(parent: Node3D, world_position: Vector3, size: float, minerals: float) -> Node:
	var data: AsteroidPlacement = AsteroidPlacement.new()
	data.position = world_position
	data.size = size
	data.minerals = minerals
	_spawn_asteroid(parent, data, null)
	var children: Array = parent.get_children()
	if children.is_empty():
		return null
	return children[children.size() - 1]


func spawn_asteroid_cloud_for_editor(parent: Node3D, cloud_data: Resource) -> void:
	var space_state: PhysicsDirectSpaceState3D = null
	if parent.is_inside_tree():
		var w: World3D = parent.get_world_3d()
		if w:
			space_state = w.direct_space_state
	_spawn_asteroid_cloud(parent, cloud_data, space_state)


## Spawn non-interactive preview spheres for an asteroid cloud (editor Test Generate)
func spawn_cloud_preview(parent: Node3D, data: Resource) -> void:
	for child in parent.get_children():
		child.queue_free()
	if data.count <= 0:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if data.seed != 0:
		rng.seed = data.seed
	else:
		rng.randomize()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.85, 0.5, 0.6)
	for _i in range(data.count):
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.0, data.radius)
		var spawn_pos: Vector3 = data.center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var size: float = rng.randf_range(data.min_size, data.max_size)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = sphere_mesh
		mi.set_surface_override_material(0, mat.duplicate())
		mi.global_position = spawn_pos
		mi.scale = Vector3(size * 0.5, size * 0.5, size * 0.5)
		parent.add_child(mi)


## Spawn a structure from placement data
func _spawn_structure(parent: Node3D, data: StructurePlacement) -> void:
	var scene: PackedScene = _get_structure_scene(data.building_type)
	if not scene:
		push_warning("Unknown structure type: " + data.building_type)
		return
	
	var structure: Node = scene.instantiate()
	if not structure:
		return
	parent.add_child(structure)
	if structure is Node3D:
		(structure as Node3D).global_position = data.position
	elif structure is Entity:
		var body: Node = structure.get_node_or_null("StructureBody")
		if body and body is Node3D:
			(body as Node3D).global_position = data.position
		if ECS and ECS.world:
			ECS.world.add_entity(structure, [], false)
		if data.is_pre_built and body and body.has_method("set_starter_panel"):
			body.call("set_starter_panel", true)
		if data.building_type == "monolith" and current_map and current_map.get("win_monolith_power_required") and current_map.win_monolith_power_required > 0 and structure.get("_pending_monolith_power_required") != null:
			structure.set("_pending_monolith_power_required", float(current_map.win_monolith_power_required))
		if data.building_type == "monolith" and data.victory_monolith and structure is Entity:
			(structure as Entity).add_component(C_VictoryMonolithClass.new())
		return
	else:
		return
	if structure is Node3D:
		if data.is_pre_built and structure.has_method("set_starter_panel"):
			structure.call("set_starter_panel", true)
		if data.building_type == "monolith" and current_map and current_map.get("win_monolith_power_required") and current_map.win_monolith_power_required > 0 and structure.get("_pending_monolith_power_required") != null:
			structure.set("_pending_monolith_power_required", float(current_map.win_monolith_power_required))


## Runtime helper for map editor placement.
func spawn_structure_for_editor(parent: Node3D, building_type: String, world_position: Vector3, pre_built: bool = true) -> Node3D:
	var data: StructurePlacement = StructurePlacement.new()
	data.building_type = building_type
	data.position = world_position
	_spawn_structure(parent, data)
	var children: Array = parent.get_children()
	if children.is_empty():
		return null
	return children[children.size() - 1] as Node3D


func get_available_structure_types() -> PackedStringArray:
	## Returns structure types from BuildManager's BuildingData (single source of truth).
	if BuildManager:
		return BuildManager.get_available_building_types()
	return PackedStringArray(["solar_panel", "power_node", "mining_station", "laser_turret", "monolith"])


## Get wave data for a specific wave number
func get_wave_data(wave_number: int) -> WaveData:
	if not current_map:
		return null
	
	if wave_number < 0 or wave_number >= current_map.waves.size():
		var ext_res: Resource = current_map.endless_extrapolation
		if ext_res != null and ext_res.has_method("build_wave"):
			return ext_res.call("build_wave", wave_number)
		var wave: WaveData = WaveData.new()
		var w: int = maxi(wave_number, 0)
		wave.wave_number = wave_number
		wave.enemy_count = int(mini(ceil(3.0 * pow(1.2, float(w))), 800))
		wave.enemy_count = maxi(wave.enemy_count, 3)
		wave.enemy_health_multiplier = 1.0 + float(w) * 0.22
		wave.enemy_speed_multiplier = 1.0 + float(w) * 0.05
		wave.spawn_delay = maxf(0.1, 1.35 - float(w) * 0.048)
		return wave
	
	return current_map.waves[wave_number]
