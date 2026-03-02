extends Node
## MapLoader - Handles loading and instantiating maps from MapData resources

const MapValidatorClass: Script = preload("res://scripts/data/map_validator.gd")

signal map_loaded(map_data: MapData)
signal map_cleared
signal map_load_failed(errors: PackedStringArray)

var current_map: MapData = null

# Scene references
var asteroid_scene: PackedScene
var _structure_scenes: Dictionary = {}


func _ready() -> void:
	_load_scenes()


func _load_scenes() -> void:
	asteroid_scene = load("res://scenes/game/asteroid.tscn")
	
	_structure_scenes = {
		"solar_panel": load("res://scenes/structures/solar_panel.tscn"),
		"power_node": load("res://scenes/structures/power_node.tscn"),
		"mining_station": load("res://scenes/structures/mining_station.tscn"),
		"laser_turret": load("res://scenes/structures/laser_turret.tscn")
	}


## Load a map from a MapData resource
func load_map(map_data: MapData) -> void:
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
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		push_error("Main scene not found")
		return
	
	# Spawn asteroids
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if asteroids_parent:
		for asteroid_data in map_data.asteroids:
			_spawn_asteroid(asteroids_parent, asteroid_data)
		for cloud_data in map_data.asteroid_clouds:
			_spawn_asteroid_cloud(asteroids_parent, cloud_data)
	
	# Spawn starting structures
	var structures_parent: Node = main.get_node_or_null("Structures")
	if structures_parent:
		for structure_data in map_data.starting_structures:
			_spawn_structure(structures_parent, structure_data)
	
	# Configure game state
	GameState.apply_map_settings(map_data)
	if EnemyManager and EnemyManager.has_method("apply_map_wave_settings"):
		EnemyManager.apply_map_wave_settings(map_data)
	
	map_loaded.emit(map_data)


## Load a map from a JSON file
func load_map_from_json(path: String) -> void:
	var map_data: MapData = MapData.load_from_json(path)
	if map_data:
		load_map(map_data)


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
	
	current_map = null
	map_cleared.emit()


## Spawn an asteroid from placement data
func _spawn_asteroid(parent: Node3D, data: AsteroidPlacement) -> void:
	if not asteroid_scene:
		return
	
	var asteroid: Asteroid = asteroid_scene.instantiate() as Asteroid
	if asteroid:
		parent.add_child(asteroid)
		asteroid.global_position = data.position
		asteroid.asteroid_size = data.size
		asteroid.set_minerals(data.minerals)


## Spawn a deterministic asteroid cloud from placement data
func _spawn_asteroid_cloud(parent: Node3D, data: Resource) -> void:
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
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.0, data.radius)
		var spawn_pos: Vector3 = data.center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var placement: AsteroidPlacement = AsteroidPlacement.new()
		placement.position = spawn_pos
		placement.size = rng.randf_range(data.min_size, data.max_size)
		placement.minerals = rng.randf_range(data.min_minerals, data.max_minerals)
		_spawn_asteroid(parent, placement)


func spawn_asteroid_for_editor(parent: Node3D, world_position: Vector3, size: float, minerals: float) -> Asteroid:
	var data: AsteroidPlacement = AsteroidPlacement.new()
	data.position = world_position
	data.size = size
	data.minerals = minerals
	_spawn_asteroid(parent, data)
	var children: Array = parent.get_children()
	if children.is_empty():
		return null
	return children[children.size() - 1] as Asteroid


func spawn_asteroid_cloud_for_editor(parent: Node3D, cloud_data: Resource) -> void:
	_spawn_asteroid_cloud(parent, cloud_data)


## Spawn a structure from placement data
func _spawn_structure(parent: Node3D, data: StructurePlacement) -> void:
	var scene: PackedScene = _structure_scenes.get(data.building_type)
	if not scene:
		push_warning("Unknown structure type: " + data.building_type)
		return
	
	var structure: Node3D = scene.instantiate() as Node3D
	if structure:
		parent.add_child(structure)
		structure.global_position = data.position
		# Must run after add_child so structure _ready() has initialized components.
		if data.is_pre_built and structure.has_method("set_starter_panel"):
			structure.set_starter_panel(true)


## Runtime helper for map editor placement.
func spawn_structure_for_editor(parent: Node3D, building_type: String, world_position: Vector3, pre_built: bool = true) -> Node3D:
	var data: StructurePlacement = StructurePlacement.new()
	data.building_type = building_type
	data.position = world_position
	data.is_pre_built = pre_built
	_spawn_structure(parent, data)
	var children: Array = parent.get_children()
	if children.is_empty():
		return null
	return children[children.size() - 1] as Node3D


func get_available_structure_types() -> PackedStringArray:
	return PackedStringArray(_structure_scenes.keys())


## Get wave data for a specific wave number
func get_wave_data(wave_number: int) -> WaveData:
	if not current_map:
		return null
	
	if wave_number < 0 or wave_number >= current_map.waves.size():
		# Generate default wave for waves beyond defined ones
		var wave: WaveData = WaveData.new()
		wave.wave_number = wave_number
		wave.enemy_count = 3 + (wave_number * 2)
		wave.enemy_health_multiplier = 1.0 + (wave_number * 0.2)
		wave.enemy_speed_multiplier = 1.0 + (wave_number * 0.05)
		return wave
	
	return current_map.waves[wave_number]
