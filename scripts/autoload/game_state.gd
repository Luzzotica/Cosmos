extends Node
## GameState Singleton - Manages global game state

signal minerals_changed(amount: int)
signal minerals_spent_changed(total_spent: int)
signal energy_changed(current: float, capacity: float)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal game_over
signal victory
## Emitted when [member SceneTree.paused] changes (backward compatible with pause UI).
signal pause_changed(paused: bool)
## Emitted after [member session_state] changes.
signal session_state_changed(prev: SessionState, next: SessionState)

enum SessionState {
	PLAYING,
	PAUSED,
	## Tree paused; no pause menu (e.g. map dialogue).
	DIALOGUE_PAUSE,
	## Dialogue runs while the match keeps simulating (waves, economy, etc.).
	DIALOGUE_REALTIME,
	WON,
	LOST,
}

## Current high-level session. Prefer this over legacy bools.
var session_state: SessionState = SessionState.PLAYING

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
## When false, [method _update_wave_timer] does not count down (e.g. during map intro dialogue).
var wave_timer_enabled: bool = false

# Game state
var game_time: float = 0.0
var total_minerals_mined: int = 0
var total_minerals_spent: int = 0
## Cumulative grid power generated this level (integral of PowerGraphManager generation rate over time).
var total_power_generated: float = 0.0

# Config
const DEFAULT_INITIAL_DELAY: float = 20.0  # 20 seconds before first wave
const DEFAULT_WAVE_INTERVAL: float = 60.0  # 60 seconds between waves

## Default HUD/build bar order when map does not set [member MapData.allowed_buildings_defined].
const DEFAULT_BUILDABLE_ORDER: Array[String] = [
	"solar_panel",
	"power_node",
	"mining_station",
	"laser_turret",
	"missile_turret",
	"repair_station",
]

## When false, [member build_allowed_buildings] is ignored (full default order, filtered by loaded BuildingData).
## When true, only [member build_allowed_buildings] may be built (empty = nothing buildable).
var build_allowed_buildings_defined: bool = false
var build_allowed_buildings: PackedStringArray = PackedStringArray()


## True when the match ended in victory or defeat.
var is_game_over: bool:
	get:
		return session_state == SessionState.WON or session_state == SessionState.LOST


## True when the player won the current level.
var is_victory: bool:
	get:
		return session_state == SessionState.WON


## True when the scene tree is paused (menu pause, dialogue freeze, or endgame).
var is_paused: bool:
	get:
		return session_state != SessionState.PLAYING and session_state != SessionState.DIALOGUE_REALTIME


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if is_paused:
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
	var cost: int = int(amount)
	if minerals >= cost:
		minerals -= cost
		total_minerals_spent += cost
		minerals_spent_changed.emit(total_minerals_spent)
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
	if not wave_timer_enabled:
		return
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
	if not wave_timer_enabled:
		return

	if not is_wave_in_progress:
		time_until_next_wave -= delta
		if time_until_next_wave <= 0:
			start_wave()


func _update_energy_balance(delta: float) -> void:
	var gen_rate: float = energy_production
	if PowerGraphManager:
		gen_rate = PowerGraphManager.get_power_generation()
	total_power_generated += gen_rate * delta
	var net_energy: float = (energy_production - energy_consumption) * delta
	add_energy(net_energy)


func trigger_game_over() -> void:
	set_session_state(SessionState.LOST)
	game_over.emit()


func trigger_victory() -> void:
	set_session_state(SessionState.WON)
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
	total_minerals_mined = 0
	total_minerals_spent = 0
	total_power_generated = 0.0
	minerals_spent_changed.emit(total_minerals_spent)
	wave_timer_enabled = false
	build_allowed_buildings_defined = false
	build_allowed_buildings = PackedStringArray()
	set_session_state(SessionState.PLAYING)


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
	total_minerals_mined = 0
	total_minerals_spent = 0
	total_power_generated = 0.0
	minerals_spent_changed.emit(total_minerals_spent)
	wave_timer_enabled = false
	if map_data.allowed_buildings_defined:
		build_allowed_buildings_defined = true
		build_allowed_buildings = map_data.allowed_buildings.duplicate()
	else:
		build_allowed_buildings_defined = false
		build_allowed_buildings = PackedStringArray()
	set_session_state(SessionState.PLAYING)


## Types shown in the build bar and accepted by [method is_building_allowed_for_current_map].
func get_effective_buildable_types() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var mgr: Node = get_node_or_null("/root/BuildManager")
	if not build_allowed_buildings_defined:
		for bid: String in DEFAULT_BUILDABLE_ORDER:
			if mgr and mgr.has_method("get_building_data") and mgr.call("get_building_data", bid):
				out.append(bid)
		return out
	for bid in build_allowed_buildings:
		if mgr and mgr.has_method("get_building_data") and mgr.call("get_building_data", bid):
			out.append(bid)
	return out


## True if [param building_type] is in the current session build palette (HUD + [method BuildManager.start_building]).
func is_building_type_in_session_build_palette(building_type: String) -> bool:
	return get_effective_buildable_types().has(building_type)


func set_wave_timer_enabled(enabled: bool) -> void:
	wave_timer_enabled = enabled


func set_session_state(next: SessionState) -> void:
	var tree: SceneTree = get_tree()
	var should_pause_tree: bool = next in [
		SessionState.PAUSED,
		SessionState.DIALOGUE_PAUSE,
		SessionState.WON,
		SessionState.LOST,
	]
	# Always sync SceneTree.paused to the target state, even when session_state is already `next`.
	# Otherwise we can desync (e.g. reset() requests PLAYING while already PLAYING after tree stayed paused).
	if session_state == next:
		if tree and tree.paused != should_pause_tree:
			tree.paused = should_pause_tree
			pause_changed.emit(tree.paused)
		return
	var prev: SessionState = session_state
	session_state = next
	if tree:
		tree.paused = should_pause_tree
	session_state_changed.emit(prev, next)
	pause_changed.emit(tree.paused if tree else false)


## Backward compatible: [code]set_paused(true)[/code] opens the pause menu; [code]set_paused(true, false)[/code] is dialogue freeze.
func set_paused(paused: bool, show_pause_menu: bool = true) -> void:
	if paused:
		set_session_state(SessionState.PAUSED if show_pause_menu else SessionState.DIALOGUE_PAUSE)
	else:
		set_session_state(SessionState.PLAYING)


func toggle_pause() -> void:
	if session_state == SessionState.WON or session_state == SessionState.LOST:
		return
	if session_state == SessionState.DIALOGUE_PAUSE:
		return
	if session_state == SessionState.DIALOGUE_REALTIME:
		set_session_state(SessionState.PAUSED)
		return
	if session_state == SessionState.PLAYING:
		set_session_state(SessionState.PAUSED)
	elif session_state == SessionState.PAUSED:
		set_session_state(SessionState.PLAYING)
