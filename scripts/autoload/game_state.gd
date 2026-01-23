extends Node
## GameState Singleton - Manages global game state

signal minerals_changed(amount: int)
signal energy_changed(current: float, capacity: float)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal game_over

# Resources
var minerals: int = 10000:
	set(value):
		minerals = value
		minerals_changed.emit(minerals)

var energy: float = 100.0:
	set(value):
		energy = clampf(value, 0.0, energy_capacity)
		energy_changed.emit(energy, energy_capacity)

var energy_capacity: float = 100.0
var energy_production: float = 0.0
var energy_consumption: float = 0.0

# Wave state
var current_wave: int = 0
var is_wave_in_progress: bool = false
var time_until_next_wave: float = 30.0

# Game state
var game_time: float = 0.0
var is_paused: bool = false
var is_game_over: bool = false

# Config
const INITIAL_DELAY: float = 90.0  # 90 seconds before first wave
const WAVE_INTERVAL: float = 60.0  # 60 seconds between waves


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if is_paused or is_game_over:
		return
	
	game_time += delta
	_update_wave_timer(delta)
	_update_energy_balance(delta)


func add_minerals(amount: float) -> void:
	minerals += int(amount)


func consume_minerals(amount: float) -> bool:
	if minerals >= int(amount):
		minerals -= int(amount)
		return true
	return false


func add_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, energy_capacity)


func consume_energy(amount: float) -> bool:
	if energy >= amount:
		energy -= amount
		return true
	return false


func increase_energy_capacity(amount: float) -> void:
	energy_capacity += amount
	energy_changed.emit(energy, energy_capacity)


func start_wave() -> void:
	is_wave_in_progress = true
	time_until_next_wave = WAVE_INTERVAL
	wave_started.emit(current_wave)


func end_wave() -> void:
	is_wave_in_progress = false
	current_wave += 1
	time_until_next_wave = 10.0
	wave_ended.emit(current_wave)


func _update_wave_timer(delta: float) -> void:
	if not is_wave_in_progress:
		time_until_next_wave -= delta
		if time_until_next_wave <= 0:
			start_wave()


func _update_energy_balance(delta: float) -> void:
	var net_energy: float = (energy_production - energy_consumption) * delta
	add_energy(net_energy)


func trigger_game_over() -> void:
	is_game_over = true
	is_paused = true
	game_over.emit()


func reset() -> void:
	minerals = 10000
	energy = 100.0
	energy_capacity = 100.0
	energy_production = 0.0
	energy_consumption = 0.0
	current_wave = 0
	is_wave_in_progress = false
	time_until_next_wave = INITIAL_DELAY
	game_time = 0.0
	is_paused = false
	is_game_over = false
