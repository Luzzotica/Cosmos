@tool
extends Resource
class_name MapData
## Resource defining a map's layout and wave configuration

const AsteroidCloudPlacementClass: Script = preload("res://scripts/data/asteroid_cloud_placement.gd")
const StartingResourcesClass: Script = preload("res://scripts/data/starting_resources.gd")
const EnemyWaveEntryClass: Script = preload("res://scripts/data/enemy_wave_entry.gd")

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION
@export var map_id: String = ""
@export var map_name: String = "New Map"
@export var description: String = ""
@export var author_id: String = ""
@export var map_size: Vector2 = Vector2(500, 500)
@export var biome: String = "asteroid_field"
@export var difficulty_band: String = "normal"
@export var act: String = ""
@export var chapter: String = ""
@export var tags: PackedStringArray = PackedStringArray()
@export var preview_image_path: String = ""
@export var target_carryover_minerals: int = 0
@export var target_carryover_energy: float = 0.0

@export_group("Win Conditions")
@export var win_minerals_mined: int = 0
@export var win_monolith_power_required: float = 0.0
@export var win_mode: String = "none"  # "minerals" | "monolith" | "both" | "none"

@export_group("Asteroids")
@export var asteroids: Array[AsteroidPlacement] = []
@export var asteroid_clouds: Array[Resource] = []

@export_group("Starting Structures")
@export var starting_structures: Array[StructurePlacement] = []
@export var starting_resources: Resource = StartingResourcesClass.new()

@export_group("Waves")
@export var waves: Array[WaveData] = []
@export var initial_wave_delay: float = 30.0
@export var wave_interval: float = 60.0
@export var allow_partial_extraction: bool = true

@export_group("Procedural Fill")
@export var procedural_seed: int = 0
@export var allow_procedural_fill: bool = false

## Optional camera look-at position [x, z] when map loads. INF means unset (fall back to first structure).
@export var camera_start_position: Vector2 = Vector2(INF, INF)


## Resolve path for web/export: try given path, then fallbacks (include_filter may flatten paths).
static func resolve_json_path(path: String) -> String:
	if FileAccess.file_exists(path):
		return path
	var filename := path.get_file()
	# Fallback: file at project root (e.g. include_filter *.json flattens)
	var root_path := "res://" + filename
	if FileAccess.file_exists(root_path):
		return root_path
	# Fallback: file in resources/ only
	var resources_path := "res://resources/" + filename
	if FileAccess.file_exists(resources_path):
		return resources_path
	return path  # Return original so error message is accurate


## Load map from JSON file
static func load_from_json(path: String) -> MapData:
	var resolved := resolve_json_path(path)
	var file: FileAccess = FileAccess.open(resolved, FileAccess.READ)
	if not file:
		push_error("Failed to open map file: " + path + " (tried: " + resolved + ")")
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
	
	map_data.schema_version = int(data.get("schema_version", CURRENT_SCHEMA_VERSION))
	map_data.map_id = String(data.get("id", ""))
	map_data.map_name = data.get("name", "Unnamed Map")
	map_data.description = String(data.get("description", ""))
	map_data.author_id = String(data.get("author_id", ""))
	
	var size_array: Array = data.get("size", [500, 500])
	map_data.map_size = Vector2(size_array[0], size_array[1])
	map_data.biome = String(data.get("biome", "asteroid_field"))
	map_data.difficulty_band = String(data.get("difficulty_band", "normal"))
	map_data.act = String(data.get("act", ""))
	map_data.chapter = String(data.get("chapter", ""))
	map_data.preview_image_path = String(data.get("preview_image_path", ""))
	map_data.target_carryover_minerals = int(data.get("target_carryover_minerals", 0))
	map_data.target_carryover_energy = float(data.get("target_carryover_energy", 0.0))
	map_data.win_minerals_mined = int(data.get("win_minerals_mined", 0))
	map_data.win_monolith_power_required = float(data.get("win_monolith_power_required", 0.0))
	map_data.win_mode = String(data.get("win_mode", "none"))
	var parsed_tags: Array = data.get("tags", [])
	map_data.tags = PackedStringArray(parsed_tags.map(func(item: Variant) -> String: return String(item)))
	
	map_data.initial_wave_delay = data.get("initial_wave_delay", 30.0)
	map_data.wave_interval = data.get("wave_interval", 60.0)
	map_data.allow_partial_extraction = bool(data.get("allow_partial_extraction", true))
	map_data.procedural_seed = int(data.get("procedural_seed", 0))
	map_data.allow_procedural_fill = bool(data.get("allow_procedural_fill", false))

	var cam_arr: Array = data.get("camera_start", [])
	if cam_arr.size() >= 2:
		map_data.camera_start_position = Vector2(float(cam_arr[0]), float(cam_arr[1]))

	# Parse asteroids
	var asteroids_data: Array = data.get("asteroids", [])
	for asteroid_dict in asteroids_data:
		var asteroid: AsteroidPlacement = AsteroidPlacement.new()
		var pos_array: Array = asteroid_dict.get("position", [0, 0, 0])
		asteroid.position = Vector3(pos_array[0], pos_array[1], pos_array[2])
		asteroid.size = asteroid_dict.get("size", 3.0)
		asteroid.minerals = asteroid_dict.get("minerals", 30.0)
		map_data.asteroids.append(asteroid)

	# Parse asteroid clouds
	var clouds_data: Array = data.get("asteroid_clouds", [])
	for cloud_dict in clouds_data:
		var cloud: Resource = AsteroidCloudPlacementClass.new()
		var center_array: Array = cloud_dict.get("center", [0, 0, 0])
		cloud.center = Vector3(center_array[0], center_array[1], center_array[2])
		cloud.radius = float(cloud_dict.get("radius", 30.0))
		cloud.count = int(cloud_dict.get("count", 6))
		cloud.min_size = float(cloud_dict.get("min_size", 2.0))
		cloud.max_size = float(cloud_dict.get("max_size", 4.0))
		cloud.min_minerals = float(cloud_dict.get("min_minerals", 25.0))
		cloud.max_minerals = float(cloud_dict.get("max_minerals", 60.0))
		cloud.seed = int(cloud_dict.get("seed", 0))
		map_data.asteroid_clouds.append(cloud)
	
	# Parse starting structures
	var structures_data: Array = data.get("starting_structures", [])
	for structure_dict in structures_data:
		var structure: StructurePlacement = StructurePlacement.new()
		structure.building_type = structure_dict.get("type", "solar_panel")
		var pos_array: Array = structure_dict.get("position", [0, 0, 0])
		structure.position = Vector3(pos_array[0], pos_array[1], pos_array[2])
		structure.is_pre_built = structure_dict.get("pre_built", true)
		map_data.starting_structures.append(structure)

	# Parse starting resources
	var resources_dict: Dictionary = data.get("starting_resources", {})
	map_data.starting_resources.minerals = int(resources_dict.get("minerals", 10000))
	map_data.starting_resources.energy = float(resources_dict.get("energy", 100.0))
	map_data.starting_resources.energy_capacity = float(resources_dict.get("energy_capacity", 100.0))
	map_data.starting_resources.override_defaults = bool(resources_dict.get("override_defaults", false))
	
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
		var composition_data: Array = wave_dict.get("enemy_composition", [])
		for composition_entry in composition_data:
			if not (composition_entry is Dictionary):
				continue
			var entry_dict: Dictionary = composition_entry
			var entry: Resource = EnemyWaveEntryClass.new()
			entry.enemy_id = String(entry_dict.get("enemy_id", "enemy_standard"))
			entry.count = int(entry_dict.get("count", 0))
			entry.spawn_weight = float(entry_dict.get("spawn_weight", 1.0))
			entry.sanitize()
			wave.enemy_composition.append(entry)
		if not wave.enemy_composition.is_empty():
			wave.enemy_count = wave.get_total_enemy_count()
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
		"schema_version": schema_version,
		"id": map_id,
		"name": map_name,
		"description": description,
		"author_id": author_id,
		"size": [map_size.x, map_size.y],
		"biome": biome,
		"difficulty_band": difficulty_band,
		"act": act,
		"chapter": chapter,
		"tags": Array(tags),
		"preview_image_path": preview_image_path,
		"target_carryover_minerals": target_carryover_minerals,
		"target_carryover_energy": target_carryover_energy,
		"win_minerals_mined": win_minerals_mined,
		"win_monolith_power_required": win_monolith_power_required,
		"win_mode": win_mode,
		"initial_wave_delay": initial_wave_delay,
		"wave_interval": wave_interval,
		"allow_partial_extraction": allow_partial_extraction,
		"procedural_seed": procedural_seed,
		"allow_procedural_fill": allow_procedural_fill,
		"asteroids": [],
		"asteroid_clouds": [],
		"starting_structures": [],
		"starting_resources": {
			"minerals": starting_resources.minerals,
			"energy": starting_resources.energy,
			"energy_capacity": starting_resources.energy_capacity,
			"override_defaults": starting_resources.override_defaults
		},
		"waves": []
	}
	
	if not is_inf(camera_start_position.x):
		data["camera_start"] = [camera_start_position.x, camera_start_position.y]

	for asteroid in asteroids:
		data.asteroids.append({
			"position": [asteroid.position.x, asteroid.position.y, asteroid.position.z],
			"size": asteroid.size,
			"minerals": asteroid.minerals
		})

	for cloud in asteroid_clouds:
		data.asteroid_clouds.append({
			"center": [cloud.center.x, cloud.center.y, cloud.center.z],
			"radius": cloud.radius,
			"count": cloud.count,
			"min_size": cloud.min_size,
			"max_size": cloud.max_size,
			"min_minerals": cloud.min_minerals,
			"max_minerals": cloud.max_minerals,
			"seed": cloud.seed
		})
	
	for structure in starting_structures:
		data.starting_structures.append({
			"type": structure.building_type,
			"position": [structure.position.x, structure.position.y, structure.position.z],
			"pre_built": structure.is_pre_built
		})
	
	for wave in waves:
		var wave_data: Dictionary = {
			"enemy_count": wave.enemy_count,
			"delay": wave.spawn_delay,
			"health_mult": wave.enemy_health_multiplier,
			"speed_mult": wave.enemy_speed_multiplier
		}
		if not wave.enemy_composition.is_empty():
			var composition_json: Array[Dictionary] = []
			for entry in wave.enemy_composition:
				if entry == null:
					continue
				composition_json.append({
					"enemy_id": String(entry.get("enemy_id")),
					"count": int(entry.get("count")),
					"spawn_weight": float(entry.get("spawn_weight"))
				})
			wave_data["enemy_composition"] = composition_json
		data.waves.append(wave_data)
	
	return data
