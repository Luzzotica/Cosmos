extends GutTest

const MapValidatorClass = preload("res://scripts/data/map_validator.gd")
const EndlessMapGeneratorClass = preload("res://scripts/game/endless_map_generator.gd")


func test_endless_map_generator_produces_valid_map_data() -> void:
	var md: MapData = EndlessMapGeneratorClass.build(12345, "normal")
	var result: Dictionary = MapValidatorClass.validate_map_data(md)
	assert_true(bool(result.get("is_valid", false)), str(result.get("errors", [])))
	assert_eq(md.win_mode, "none")
	assert_false(md.asteroid_clouds.is_empty())
	assert_eq(md.asteroid_clouds.size(), 8)
	assert_eq((md.asteroid_clouds[0] as AsteroidCloudPlacement).center, Vector3.ZERO)
	assert_true(md.waves.is_empty())
	assert_eq(md.starting_structures.size(), 1)
	assert_not_null(md.endless_extrapolation)


func test_map_loader_extrapolated_wave_scales_stats_and_exponential_count() -> void:
	var md: MapData = EndlessMapGeneratorClass.build(42, "normal")
	var map_loader: Node = get_node_or_null("/root/MapLoader")
	assert_not_null(map_loader)
	map_loader.current_map = md
	var w: WaveData = map_loader.get_wave_data(10)
	assert_not_null(w)
	assert_eq(w.enemy_count, int(ceil(3.0 * pow(1.2, 10.0))))
	assert_true(w.enemy_health_multiplier > 1.0)
	assert_true(w.spawn_delay < 1.5)
	map_loader.current_map = null


func test_endless_easy_vs_hard_extrapolation_differs() -> void:
	var md_easy: MapData = EndlessMapGeneratorClass.build(99, "easy")
	var md_hard: MapData = EndlessMapGeneratorClass.build(99, "hard")
	var map_loader: Node = get_node_or_null("/root/MapLoader")
	map_loader.current_map = md_easy
	var w_easy: WaveData = map_loader.get_wave_data(5)
	map_loader.current_map = md_hard
	var w_hard: WaveData = map_loader.get_wave_data(5)
	map_loader.current_map = null
	assert_true(w_hard.enemy_count >= w_easy.enemy_count)
	assert_true(w_hard.enemy_health_multiplier >= w_easy.enemy_health_multiplier)
