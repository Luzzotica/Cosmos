class_name EndlessWaveExtrapolation
extends Resource
## Coefficients for extrapolated waves when authored [member MapData.waves] is empty or exhausted.

@export var count_base: float = 3.0
@export var count_growth: float = 1.2
@export var count_cap: int = 800
@export var health_add_per_wave: float = 0.22
@export var speed_add_per_wave: float = 0.05
@export var spawn_delay_start: float = 1.35
@export var spawn_delay_per_wave: float = 0.048
@export var spawn_delay_min: float = 0.1


func build_wave(wave_number: int) -> WaveData:
	var w: int = maxi(wave_number, 0)
	var wave: WaveData = WaveData.new()
	wave.wave_number = wave_number
	var raw_count: float = count_base * pow(count_growth, float(w))
	wave.enemy_count = int(mini(ceilf(raw_count), float(count_cap)))
	wave.enemy_count = maxi(wave.enemy_count, 3)
	wave.enemy_health_multiplier = 1.0 + float(w) * health_add_per_wave
	wave.enemy_speed_multiplier = 1.0 + float(w) * speed_add_per_wave
	wave.spawn_delay = maxf(spawn_delay_min, spawn_delay_start - float(w) * spawn_delay_per_wave)
	return wave
