@tool
extends Resource
class_name MapData
## Resource defining a map's layout and wave configuration

@export var map_name: String = "New Map"
@export var map_size: Vector2 = Vector2(500, 500)

@export_group("Asteroids")
@export var asteroids: Array[AsteroidPlacement] = []

@export_group("Starting Structures")
@export var starting_structures: Array[StructurePlacement] = []

@export_group("Waves")
@export var waves: Array[WaveData] = []
@export var initial_wave_delay: float = 30.0
@export var wave_interval: float = 60.0


## Load map from JSON file
static func load_from_json(path: String) -> MapData:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open map file: " + path)
		return null
	
	var json_text: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	var error: Error = json.parse(json_text)
	if error != OK:
		push_error("Failed to parse map JSON: " + json.get_error_message())
		return null
	
	var data: Dictionary = json.data
	return _create_from_dict(data)


## Create MapData from dictionary (parsed JSON)
static func _create_from_dict(data: Dictionary) -> MapData:
	var map_data: MapData = MapData.new()
	
	map_data.map_name = data.get("name", "Unnamed Map")
	
	var size_array: Array = data.get("size", [500, 500])
	map_data.map_size = Vector2(size_array[0], size_array[1])
	
	map_data.initial_wave_delay = data.get("initial_wave_delay", 30.0)
	map_data.wave_interval = data.get("wave_interval", 60.0)
	
	# Parse asteroids
	var asteroids_data: Array = data.get("asteroids", [])
	for asteroid_dict in asteroids_data:
		var asteroid: AsteroidPlacement = AsteroidPlacement.new()
		var pos_array: Array = asteroid_dict.get("position", [0, 0, 0])
		asteroid.position = Vector3(pos_array[0], pos_array[1], pos_array[2])
		asteroid.size = asteroid_dict.get("size", 3.0)
		asteroid.minerals = asteroid_dict.get("minerals", 30.0)
		map_data.asteroids.append(asteroid)
	
	# Parse starting structures
	var structures_data: Array = data.get("starting_structures", [])
	for structure_dict in structures_data:
		var structure: StructurePlacement = StructurePlacement.new()
		structure.building_type = structure_dict.get("type", "solar_panel")
		var pos_array: Array = structure_dict.get("position", [0, 0, 0])
		structure.position = Vector3(pos_array[0], pos_array[1], pos_array[2])
		structure.is_pre_built = structure_dict.get("pre_built", true)
		map_data.starting_structures.append(structure)
	
	# Parse waves
	var waves_data: Array = data.get("waves", [])
	for i in range(waves_data.size()):
		var wave_dict: Dictionary = waves_data[i]
		var wave: WaveData = WaveData.new()
		wave.wave_number = i
		wave.enemy_count = wave_dict.get("enemy_count", 3)
		wave.spawn_delay = wave_dict.get("delay", 2.0)
		wave.enemy_health_multiplier = wave_dict.get("health_mult", 1.0)
		wave.enemy_speed_multiplier = wave_dict.get("speed_mult", 1.0)
		map_data.waves.append(wave)
	
	return map_data


## Save map to JSON file
func save_to_json(path: String) -> bool:
	var data: Dictionary = _to_dict()
	var json_text: String = JSON.stringify(data, "\t")
	
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: " + path)
		return false
	
	file.store_string(json_text)
	file.close()
	return true


## Convert to dictionary for JSON serialization
func _to_dict() -> Dictionary:
	var data: Dictionary = {
		"name": map_name,
		"size": [map_size.x, map_size.y],
		"initial_wave_delay": initial_wave_delay,
		"wave_interval": wave_interval,
		"asteroids": [],
		"starting_structures": [],
		"waves": []
	}
	
	for asteroid in asteroids:
		data.asteroids.append({
			"position": [asteroid.position.x, asteroid.position.y, asteroid.position.z],
			"size": asteroid.size,
			"minerals": asteroid.minerals
		})
	
	for structure in starting_structures:
		data.starting_structures.append({
			"type": structure.building_type,
			"position": [structure.position.x, structure.position.y, structure.position.z],
			"pre_built": structure.is_pre_built
		})
	
	for wave in waves:
		data.waves.append({
			"enemy_count": wave.enemy_count,
			"delay": wave.spawn_delay,
			"health_mult": wave.enemy_health_multiplier,
			"speed_mult": wave.enemy_speed_multiplier
		})
	
	return data
