extends Node
## GameState Singleton - Manages global game state

signal minerals_changed(amount: int)
signal energy_changed(current: float, capacity: float)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal game_over
signal victory
signal pause_changed(paused: bool)

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
var map_initial_wave_delay: float = 20.0
var map_wave_interval: float = 60.0

# Game state
var game_time: float = 0.0
var is_paused: bool = false
var is_game_over: bool = false
var is_victory: bool = false
var total_minerals_mined: int = 0

# Config
const DEFAULT_INITIAL_DELAY: float = 20.0  # 20 seconds before first wave
const DEFAULT_WAVE_INTERVAL: float = 60.0  # 60 seconds between waves


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


func add_minerals_from_mining(amount: float) -> void:
	var amt: int = int(amount)
	minerals += amt
	total_minerals_mined += amt


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
	time_until_next_wave = map_wave_interval
	wave_started.emit(current_wave)


func end_wave() -> void:
	is_wave_in_progress = false
	current_wave += 1
	time_until_next_wave = 10.0
	wave_ended.emit(current_wave)


func _update_wave_timer(delta: float) -> void:
	# Only run wave timer when in the main game scene (prevents spawning on main menu).
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return
	var scene_path: String = tree.current_scene.scene_file_path
	if scene_path != "res://scenes/game/main.tscn":
		return

	if not is_wave_in_progress:
		time_until_next_wave -= delta
		if time_until_next_wave <= 0:
			start_wave()


func _update_energy_balance(delta: float) -> void:
	var net_energy: float = (energy_production - energy_consumption) * delta
	add_energy(net_energy)


func trigger_game_over() -> void:
	is_game_over = true
	is_victory = false
	set_paused(true)
	game_over.emit()


func trigger_victory() -> void:
	is_game_over = true
	is_victory = true
	set_paused(true)
	victory.emit()


func reset() -> void:
	minerals = 500
	energy = 100.0
	energy_capacity = 100.0
	map_initial_wave_delay = DEFAULT_INITIAL_DELAY
	map_wave_interval = DEFAULT_WAVE_INTERVAL
	energy_production = 0.0
	energy_consumption = 0.0
	current_wave = 0
	is_wave_in_progress = false
	time_until_next_wave = map_initial_wave_delay
	game_time = 0.0
	is_game_over = false
	is_victory = false
	total_minerals_mined = 0
	set_paused(false)


func apply_map_settings(map_data: MapData) -> void:
	if not map_data:
		return

	current_wave = 0
	is_wave_in_progress = false
	map_initial_wave_delay = map_data.initial_wave_delay
	map_wave_interval = map_data.wave_interval
	time_until_next_wave = map_initial_wave_delay

	if map_data.starting_resources and map_data.starting_resources.override_defaults:
		minerals = map_data.starting_resources.minerals
		energy_capacity = map_data.starting_resources.energy_capacity
		energy = clampf(map_data.starting_resources.energy, 0.0, energy_capacity)
		energy_changed.emit(energy, energy_capacity)
	else:
		minerals = 500
		energy_capacity = 100.0
		energy = 100.0

	game_time = 0.0
	is_game_over = false
	is_victory = false
	total_minerals_mined = 0
	set_paused(false)


func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	var tree: SceneTree = get_tree()
	if tree:
		tree.paused = paused
	pause_changed.emit(is_paused)


func toggle_pause() -> void:
	if is_game_over:
		return
	set_paused(not is_paused)
