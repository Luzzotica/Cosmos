extends RefCounted
class_name MapValidator
## Static validation for map contract enforcement.

const _ALLOWED_TOP_LEVEL_KEYS: Array[String] = [
	"schema_version",
	"id",
	"name",
	"description",
	"author_id",
	"size",
	"biome",
	"difficulty_band",
	"act",
	"chapter",
	"tags",
	"preview_image_path",
	"target_carryover_minerals",
	"target_carryover_energy",
	"initial_wave_delay",
	"wave_interval",
	"allow_partial_extraction",
	"procedural_seed",
	"allow_procedural_fill",
	"asteroids",
	"asteroid_clouds",
	"starting_structures",
	"starting_resources",
	"waves"
]

const _ALLOWED_STRUCTURE_TYPES: Array[String] = [
	"solar_panel",
	"power_node",
	"mining_station",
	"laser_turret"
]


static func validate_json_dict(data: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"is_valid": true,
		"errors": PackedStringArray(),
		"warnings": PackedStringArray()
	}

	for key in data.keys():
		var key_name: String = String(key)
		if not _ALLOWED_TOP_LEVEL_KEYS.has(key_name):
			_append_error(result, "Unknown top-level key: %s" % key_name)

	return result


static func validate_map_data(map_data: MapData) -> Dictionary:
	var result: Dictionary = {
		"is_valid": true,
		"errors": PackedStringArray(),
		"warnings": PackedStringArray()
	}

	if map_data == null:
		_append_error(result, "MapData is null")
		return result

	if map_data.schema_version <= 0:
		_append_error(result, "schema_version must be positive")

	if map_data.map_name.strip_edges().is_empty():
		_append_error(result, "Map name cannot be empty")

	if map_data.map_size.x <= 0.0 or map_data.map_size.y <= 0.0:
		_append_error(result, "map_size must be positive")

	if map_data.initial_wave_delay < 0.0:
		_append_error(result, "initial_wave_delay cannot be negative")

	if map_data.wave_interval <= 0.0:
		_append_error(result, "wave_interval must be greater than zero")

	if map_data.target_carryover_minerals < 0:
		_append_error(result, "target_carryover_minerals cannot be negative")
	if map_data.target_carryover_energy < 0.0:
		_append_error(result, "target_carryover_energy cannot be negative")

	if map_data.starting_resources:
		if map_data.starting_resources.minerals < 0:
			_append_error(result, "starting_resources.minerals cannot be negative")
		if map_data.starting_resources.energy < 0.0:
			_append_error(result, "starting_resources.energy cannot be negative")
		if map_data.starting_resources.energy_capacity < 1.0:
			_append_error(result, "starting_resources.energy_capacity must be >= 1")
		if map_data.starting_resources.energy > map_data.starting_resources.energy_capacity:
			_append_warning(result, "starting_resources.energy exceeds energy_capacity and will be clamped")

	for i in range(map_data.asteroids.size()):
		var asteroid: AsteroidPlacement = map_data.asteroids[i]
		var label: String = "asteroids[%d]" % i
		if asteroid == null:
			_append_error(result, "%s is null" % label)
			continue
		if not _is_inside_bounds(asteroid.position, map_data.map_size):
			_append_error(result, "%s position is outside map bounds" % label)
		if asteroid.size <= 0.0:
			_append_error(result, "%s size must be > 0" % label)
		if asteroid.minerals < 0.0:
			_append_error(result, "%s minerals cannot be negative" % label)

	for i in range(map_data.asteroid_clouds.size()):
		var cloud: Resource = map_data.asteroid_clouds[i]
		var label: String = "asteroid_clouds[%d]" % i
		if cloud == null:
			_append_error(result, "%s is null" % label)
			continue
		if not _is_inside_bounds(cloud.center, map_data.map_size):
			_append_error(result, "%s center is outside map bounds" % label)
		if cloud.radius <= 0.0:
			_append_error(result, "%s radius must be > 0" % label)
		if cloud.count < 0:
			_append_error(result, "%s count cannot be negative" % label)
		if cloud.max_size < cloud.min_size:
			_append_error(result, "%s max_size must be >= min_size" % label)
		if cloud.max_minerals < cloud.min_minerals:
			_append_error(result, "%s max_minerals must be >= min_minerals" % label)

	for i in range(map_data.starting_structures.size()):
		var structure: StructurePlacement = map_data.starting_structures[i]
		var label: String = "starting_structures[%d]" % i
		if structure == null:
			_append_error(result, "%s is null" % label)
			continue
		if not _ALLOWED_STRUCTURE_TYPES.has(structure.building_type):
			_append_error(result, "%s has unsupported type '%s'" % [label, structure.building_type])
		if not _is_inside_bounds(structure.position, map_data.map_size):
			_append_error(result, "%s position is outside map bounds" % label)

	for i in range(map_data.waves.size()):
		var wave: WaveData = map_data.waves[i]
		var label: String = "waves[%d]" % i
		if wave == null:
			_append_error(result, "%s is null" % label)
			continue
		if wave.enemy_count < 0:
			_append_error(result, "%s enemy_count cannot be negative" % label)
		if wave.spawn_delay <= 0.0:
			_append_error(result, "%s spawn_delay must be > 0" % label)
		if wave.enemy_health_multiplier <= 0.0:
			_append_error(result, "%s enemy_health_multiplier must be > 0" % label)
		if wave.enemy_speed_multiplier <= 0.0:
			_append_error(result, "%s enemy_speed_multiplier must be > 0" % label)
		if not wave.enemy_composition.is_empty():
			var composition_total: int = 0
			for j in range(wave.enemy_composition.size()):
				var entry: Resource = wave.enemy_composition[j]
				if entry == null:
					_append_error(result, "%s enemy_composition[%d] is null" % [label, j])
					continue
				var entry_enemy_id: String = String(entry.get("enemy_id"))
				var entry_count: int = int(entry.get("count"))
				if entry_enemy_id.strip_edges().is_empty():
					_append_error(result, "%s enemy_composition[%d] enemy_id is empty" % [label, j])
				if entry_count < 0:
					_append_error(result, "%s enemy_composition[%d] count cannot be negative" % [label, j])
				composition_total += max(entry_count, 0)
			if composition_total != wave.enemy_count and composition_total > 0:
				_append_warning(result, "%s enemy_count differs from enemy_composition total; composition total will be used" % label)

	if map_data.starting_structures.is_empty():
		_append_warning(result, "Map has no starting_structures")
	if map_data.asteroids.is_empty() and map_data.asteroid_clouds.is_empty():
		_append_warning(result, "Map has no asteroid resources")

	result["is_valid"] = (result["errors"] as PackedStringArray).is_empty()
	return result


static func _is_inside_bounds(pos: Vector3, map_size: Vector2) -> bool:
	var half_x: float = map_size.x * 0.5
	var half_z: float = map_size.y * 0.5
	return pos.x >= -half_x and pos.x <= half_x and pos.z >= -half_z and pos.z <= half_z


static func _append_error(result: Dictionary, message: String) -> void:
	var errors: PackedStringArray = result["errors"]
	errors.append(message)
	result["errors"] = errors
	result["is_valid"] = false


static func _append_warning(result: Dictionary, message: String) -> void:
	var warnings: PackedStringArray = result["warnings"]
	warnings.append(message)
	result["warnings"] = warnings
