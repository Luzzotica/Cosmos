extends GutTest


func test_map_data_round_trip_preserves_new_fields() -> void:
	var map_data: MapData = MapData.new()
	map_data.schema_version = 1
	map_data.map_id = "round_trip_test"
	map_data.map_name = "Round Trip"
	map_data.biome = "nebula"
	map_data.difficulty_band = "hard"
	map_data.act = "act_02"
	map_data.chapter = "chapter_04_the_grind"
	map_data.allow_partial_extraction = true
	map_data.target_carryover_minerals = 5000
	map_data.target_carryover_energy = 125.0
	map_data.starting_resources.override_defaults = true
	map_data.starting_resources.minerals = 9000
	map_data.starting_resources.energy = 90.0
	map_data.starting_resources.energy_capacity = 120.0

	var cloud: AsteroidCloudPlacement = AsteroidCloudPlacement.new()
	cloud.center = Vector3(10, 0, 20)
	cloud.radius = 40.0
	cloud.count = 8
	cloud.seed = 1234
	map_data.asteroid_clouds.append(cloud)
	map_data.dialogue = {"start": "~ test\n=> END"}
	map_data.dialogue_realtime = true
	var mono: StructurePlacement = StructurePlacement.new()
	mono.building_type = "monolith"
	mono.position = Vector3(1, 0, 2)
	mono.victory_monolith = false
	map_data.starting_structures.append(mono)

	map_data.allowed_buildings_defined = true
	map_data.allowed_buildings = PackedStringArray(["power_node", "mining_station"])

	var serialized: Dictionary = map_data._to_dict()
	var parsed: MapData = MapData._create_from_dict(serialized)

	assert_eq(parsed.map_id, "round_trip_test")
	assert_eq(String(parsed.dialogue.get("start", "")), "~ test\n=> END")
	assert_eq(parsed.starting_structures.size(), 1)
	assert_eq(parsed.starting_structures[0].victory_monolith, false)
	assert_true(parsed.dialogue_realtime)
	assert_eq(parsed.biome, "nebula")
	assert_eq(parsed.target_carryover_minerals, 5000)
	assert_eq(parsed.asteroid_clouds.size(), 1)
	assert_eq(parsed.starting_resources.minerals, 9000)
	assert_true(parsed.allowed_buildings_defined)
	assert_eq(parsed.allowed_buildings.size(), 2)
	assert_eq(parsed.allowed_buildings[0], "power_node")
	assert_eq(parsed.allowed_buildings[1], "mining_station")


func test_validator_rejects_unknown_allowed_building_in_json_dict() -> void:
	var data: Dictionary = {
		"schema_version": 1,
		"name": "Ab",
		"allowed_buildings": ["not_a_registered_building_id"],
	}
	var result: Dictionary = MapValidator.validate_json_dict(data)
	assert_false(result.get("is_valid", true))


func test_validator_rejects_unknown_allowed_building_in_map_data() -> void:
	var map_data: MapData = MapData.new()
	map_data.map_name = "Allowed Buildings Check"
	map_data.allowed_buildings_defined = true
	map_data.allowed_buildings = PackedStringArray(["laser_turret", "fake_type"])

	var result: Dictionary = MapValidator.validate_map_data(map_data)
	assert_false(result.get("is_valid", true))


func test_validator_rejects_invalid_structure_type() -> void:
	var map_data: MapData = MapData.new()
	map_data.map_name = "Invalid Structure"

	var structure: StructurePlacement = StructurePlacement.new()
	structure.building_type = "invalid_structure"
	structure.position = Vector3.ZERO
	map_data.starting_structures.append(structure)

	var result: Dictionary = MapValidator.validate_map_data(map_data)
	assert_false(result.get("is_valid", true))
	assert_true((result.get("errors", PackedStringArray()) as PackedStringArray).size() > 0)


func test_story_constraints_require_minimum_starting_structures() -> void:
	var map_data: MapData = MapData.new()
	map_data.map_name = "Story Rule Check"
	map_data.chapter = "chapter_04_the_grind"
	map_data.difficulty_band = "hard"

	var result: Dictionary = StoryMapConstraints.validate_story_map(map_data)
	assert_false(result.get("is_valid", true))
	assert_true((result.get("errors", PackedStringArray()) as PackedStringArray).size() > 0)
