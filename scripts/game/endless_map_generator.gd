extends RefCounted
class_name EndlessMapGenerator
## Builds a validated MapData for survival/endless runs (procedural clouds, no win condition).

const AsteroidCloudPlacementClass = preload("res://scripts/data/asteroid_cloud_placement.gd")
const StartingResourcesClass = preload("res://scripts/data/starting_resources.gd")
const EndlessDifficultyPresetsScript: Script = preload("res://scripts/data/endless_difficulty_presets.gd")
const MAP_SIZE: Vector2 = Vector2(500, 500)
## Distant clouds start outside this radius so the home field stays the obvious nearby patch.
const SPAWN_CLEAR_RADIUS: float = 55.0
## One cloud around map center (player) + seven in the outer field (was 5 distant + 3 more).
const CLOUD_COUNT_DISTANT: int = 7


static func build(seed: int, difficulty_id: String = "normal") -> MapData:
	var md: MapData = MapData.new()
	md.schema_version = MapData.CURRENT_SCHEMA_VERSION
	md.map_id = "endless_survival"
	md.map_name = "Endless Run"
	md.description = "Procedural survival. Hold the line as long as you can."
	md.map_size = MAP_SIZE
	md.biome = "asteroid_field"
	md.difficulty_band = "endless"
	md.win_mode = "none"
	md.procedural_seed = seed
	var presets = EndlessDifficultyPresetsScript.new()
	var preset: Dictionary = presets.get_preset(difficulty_id)
	md.initial_wave_delay = float(preset.get("initial_wave_delay", 30.0))
	md.wave_interval = float(preset.get("wave_interval", 60.0))
	var ext: Resource = preset.get("extrapolation", null) as Resource
	if ext:
		md.endless_extrapolation = ext.duplicate()
	md.camera_start_position = Vector2(0.0, 0.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# Home asteroid field: centered on the player / map origin so there is always ore close by.
	var home: Resource = AsteroidCloudPlacementClass.new()
	home.center = Vector3.ZERO
	home.radius = rng.randf_range(26.0, 36.0)
	home.count = rng.randi_range(7, 11)
	home.min_size = rng.randf_range(2.0, 3.0)
	home.max_size = rng.randf_range(home.min_size + 0.5, 5.0)
	home.min_minerals = rng.randf_range(500.0, 1000.0)
	home.max_minerals = rng.randf_range(home.min_minerals + 100.0, 1800.0)
	home.seed = int(seed + 777000)
	md.asteroid_clouds.append(home)

	for i in range(CLOUD_COUNT_DISTANT):
		var cloud: Resource = AsteroidCloudPlacementClass.new()
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(SPAWN_CLEAR_RADIUS + 15.0, 200.0)
		var cx: float = cos(angle) * dist
		var cz: float = sin(angle) * dist
		cloud.center = Vector3(cx, 0.0, cz)
		cloud.radius = rng.randf_range(22.0, 42.0)
		cloud.count = rng.randi_range(5, 10)
		cloud.min_size = rng.randf_range(2.0, 3.0)
		cloud.max_size = rng.randf_range(cloud.min_size + 0.5, 5.0)
		cloud.min_minerals = rng.randf_range(400.0, 900.0)
		cloud.max_minerals = rng.randf_range(cloud.min_minerals + 100.0, 1800.0)
		cloud.seed = int(seed + i * 1000003)
		md.asteroid_clouds.append(cloud)

	var sp: StructurePlacement = StructurePlacement.new()
	sp.building_type = "solar_panel"
	sp.position = Vector3.ZERO
	sp.is_pre_built = true
	md.starting_structures.append(sp)

	var sr: Resource = StartingResourcesClass.new()
	sr.override_defaults = true
	sr.minerals = 450
	sr.energy = 100.0
	sr.energy_capacity = 100.0
	md.starting_resources = sr

	return md
