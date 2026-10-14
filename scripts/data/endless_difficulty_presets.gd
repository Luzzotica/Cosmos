extends RefCounted
## Preset timing + extrapolation for each endless tier. Instantiated from [member EndlessMapGenerator] only.

const EndlessWaveExtrapolationScript: Script = preload("res://scripts/data/endless_wave_extrapolation.gd")

const ID_EASY: String = "easy"
const ID_NORMAL: String = "normal"
const ID_HARD: String = "hard"
const ID_IMPOSSIBLE: String = "impossible"


func get_preset(difficulty_id: String) -> Dictionary:
	match difficulty_id:
		ID_EASY:
			return _preset_easy()
		ID_HARD:
			return _preset_hard()
		ID_IMPOSSIBLE:
			return _preset_impossible()
		_:
			return _preset_normal()


func _preset_easy() -> Dictionary:
	var ext = EndlessWaveExtrapolationScript.new()
	ext.count_base = 2.5
	ext.count_growth = 1.14
	ext.count_cap = 500
	ext.health_add_per_wave = 0.014
	ext.speed_add_per_wave = 0.035
	ext.spawn_delay_start = 1.55
	ext.spawn_delay_per_wave = 0.04
	ext.spawn_delay_min = 0.12
	return {
		"initial_wave_delay": 40.0,
		"wave_interval": 75.0,
		"extrapolation": ext,
	}


func _preset_normal() -> Dictionary:
	var ext = EndlessWaveExtrapolationScript.new()
	ext.count_base = 3.0
	ext.count_growth = 1.2
	ext.count_cap = 800
	ext.health_add_per_wave = 0.022
	ext.speed_add_per_wave = 0.05
	ext.spawn_delay_start = 1.35
	ext.spawn_delay_per_wave = 0.048
	ext.spawn_delay_min = 0.1
	return {
		"initial_wave_delay": 30.0,
		"wave_interval": 60.0,
		"extrapolation": ext,
	}


func _preset_hard() -> Dictionary:
	var ext = EndlessWaveExtrapolationScript.new()
	ext.count_base = 3.5
	ext.count_growth = 1.22
	ext.count_cap = 900
	ext.health_add_per_wave = 0.028
	ext.speed_add_per_wave = 0.065
	ext.spawn_delay_start = 1.2
	ext.spawn_delay_per_wave = 0.052
	ext.spawn_delay_min = 0.09
	return {
		"initial_wave_delay": 22.0,
		"wave_interval": 48.0,
		"extrapolation": ext,
	}


func _preset_impossible() -> Dictionary:
	var ext = EndlessWaveExtrapolationScript.new()
	ext.count_base = 4.0
	ext.count_growth = 1.24
	ext.count_cap = 1000
	ext.health_add_per_wave = 0.034
	ext.speed_add_per_wave = 0.08
	ext.spawn_delay_start = 1.05
	ext.spawn_delay_per_wave = 0.055
	ext.spawn_delay_min = 0.08
	return {
		"initial_wave_delay": 15.0,
		"wave_interval": 36.0,
		"extrapolation": ext,
	}
