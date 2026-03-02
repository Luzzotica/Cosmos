extends RefCounted
class_name StoryMapConstraints
## Story-specific map authoring constraints used by campaign tooling.

const _CHAPTER_CONSTRAINTS: Dictionary = {
	"chapter_01_first_light": {
		"recommended_difficulty": "easy",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_02_the_pattern": {
		"recommended_difficulty": "easy",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_03_hope_burns": {
		"recommended_difficulty": "normal",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_04_the_grind": {
		"recommended_difficulty": "hard",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_05_the_unease": {
		"recommended_difficulty": "hard",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_06_the_revelation": {
		"recommended_difficulty": "normal",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	},
	"chapter_07_the_dilemma": {
		"recommended_difficulty": "hard",
		"min_starting_structures": 1,
		"allow_partial_extraction": true
	}
}


static func validate_story_map(map_data: MapData) -> Dictionary:
	var result: Dictionary = {
		"is_valid": true,
		"errors": PackedStringArray(),
		"warnings": PackedStringArray()
	}

	if map_data.chapter.is_empty():
		return result

	var rules: Dictionary = _CHAPTER_CONSTRAINTS.get(map_data.chapter, {})
	if rules.is_empty():
		_append_warning(result, "No story constraints configured for chapter '%s'" % map_data.chapter)
		return result

	var expected_difficulty: String = String(rules.get("recommended_difficulty", ""))
	if not expected_difficulty.is_empty() and map_data.difficulty_band != expected_difficulty:
		_append_warning(
			result,
			"Difficulty '%s' differs from chapter recommendation '%s'" % [map_data.difficulty_band, expected_difficulty]
		)

	var min_structures: int = int(rules.get("min_starting_structures", 0))
	if map_data.starting_structures.size() < min_structures:
		_append_error(
			result,
			"Chapter '%s' requires at least %d starting structure(s)" % [map_data.chapter, min_structures]
		)

	var partial_allowed: bool = bool(rules.get("allow_partial_extraction", true))
	if map_data.allow_partial_extraction != partial_allowed:
		_append_warning(
			result,
			"allow_partial_extraction=%s differs from chapter guideline (%s)" %
			[str(map_data.allow_partial_extraction), str(partial_allowed)]
		)

	result["is_valid"] = (result["errors"] as PackedStringArray).is_empty()
	return result


static func _append_error(result: Dictionary, message: String) -> void:
	var errors: PackedStringArray = result["errors"]
	errors.append(message)
	result["errors"] = errors
	result["is_valid"] = false


static func _append_warning(result: Dictionary, message: String) -> void:
	var warnings: PackedStringArray = result["warnings"]
	warnings.append(message)
	result["warnings"] = warnings
