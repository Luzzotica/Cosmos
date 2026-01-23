extends Node
## MapLoader - Handles loading and instantiating maps from MapData resources

signal map_loaded(map_data: MapData)
signal map_cleared

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
	
	# Spawn starting structures
	var structures_parent: Node = main.get_node_or_null("Structures")
	if structures_parent:
		for structure_data in map_data.starting_structures:
			_spawn_structure(structures_parent, structure_data)
	
	# Configure game state
	GameState.time_until_next_wave = map_data.initial_wave_delay
	
	map_loaded.emit(map_data)


## Load a map from a JSON file
func load_map_from_json(path: String) -> void:
	var map_data: MapData = MapData.load_from_json(path)
	if map_data:
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
		asteroid.global_position = data.position
		asteroid.asteroid_size = data.size
		asteroid.set_minerals(data.minerals)
		parent.add_child(asteroid)


## Spawn a structure from placement data
func _spawn_structure(parent: Node3D, data: StructurePlacement) -> void:
	var scene: PackedScene = _structure_scenes.get(data.building_type)
	if not scene:
		push_warning("Unknown structure type: " + data.building_type)
		return
	
	var structure: Node3D = scene.instantiate() as Node3D
	if structure:
		structure.global_position = data.position
		if data.is_pre_built and structure.has_method("set_starter_panel"):
			structure.set_starter_panel(true)
		parent.add_child(structure)


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
