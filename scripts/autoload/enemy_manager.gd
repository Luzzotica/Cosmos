extends Node
## EnemyManager Singleton - Manages enemy spawning and waves

signal enemy_spawned(enemy: Node3D)
signal enemy_destroyed(enemy: Node3D)
signal wave_started(wave_number: int, total_enemies: int)
signal wave_completed(wave_number: int)

const BASE_ENEMIES_PER_WAVE: int = 3
const SPAWN_DELAY: float = 2.0
const DEFAULT_DETECTION_RANGE: float = 300.0
const DEFAULT_ATTACK_RANGE: float = 200.0
const SPAWN_EDGE_RADIUS: float = 170.0
const GROUP_SIZE_MIN: int = 2
const GROUP_SIZE_MAX: int = 4
const GROUP_SPREAD: float = 16.0

var _active_enemies: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _enemies_spawned_this_wave: int = 0
var _total_enemies_for_current_wave: int = BASE_ENEMIES_PER_WAVE
var _first_wave_started: bool = false
var _current_group_remaining: int = 0
var _current_group_center: Vector3 = Vector3.ZERO
var _current_group_tangent: Vector3 = Vector3.RIGHT
var _current_spawn_delay: float = SPAWN_DELAY

var enemy_scene: PackedScene = null


func _ready() -> void:
	# Try to load enemy scene
	if ResourceLoader.exists("res://scenes/enemies/enemy_ship.tscn"):
		enemy_scene = load("res://scenes/enemies/enemy_ship.tscn")
	
	# Connect to game state signals
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)
	
	# Start first wave after delay
	_schedule_first_wave()


func _schedule_first_wave() -> void:
	# Don't force start wave - let GameState timer handle it based on INITIAL_DELAY
	# This respects the 90 second initial delay
	pass


func _process(delta: float) -> void:
	if GameState.is_paused or GameState.is_game_over:
		return
	
	if GameState.is_wave_in_progress:
		_spawn_timer += delta
		
		if _spawn_timer >= _current_spawn_delay and _enemies_spawned_this_wave < _total_enemies_for_current_wave:
			_spawn_enemy()
			_spawn_timer = 0.0
			_enemies_spawned_this_wave += 1
		
		# Clean up destroyed enemies
		_active_enemies = _active_enemies.filter(func(e): return is_instance_valid(e) and not e.is_destroyed)
		
		# Check if wave is complete
		if _enemies_spawned_this_wave >= _total_enemies_for_current_wave and _active_enemies.is_empty():
			GameState.end_wave()
			_enemies_spawned_this_wave = 0
			_total_enemies_for_current_wave = _get_enemies_for_wave(GameState.current_wave)
			wave_completed.emit(GameState.current_wave - 1)


func _on_wave_started(wave_number: int) -> void:
	var map_wave: WaveData = null
	if MapLoader and MapLoader.has_method("get_wave_data"):
		map_wave = MapLoader.get_wave_data(wave_number)

	if map_wave:
		_total_enemies_for_current_wave = map_wave.enemy_count
		_current_spawn_delay = map_wave.spawn_delay
	else:
		_total_enemies_for_current_wave = _get_enemies_for_wave(wave_number)
		_current_spawn_delay = SPAWN_DELAY
	wave_started.emit(wave_number, _total_enemies_for_current_wave)


func _on_wave_ended(_wave_number: int) -> void:
	pass


## Calculate number of enemies for a given wave
func _get_enemies_for_wave(wave_number: int) -> int:
	# Gradual scaling: 3 enemies for wave 1, 5 for wave 2, 7 for wave 3, etc.
	return BASE_ENEMIES_PER_WAVE + (wave_number * 2)


## Spawn a single enemy
func _spawn_enemy() -> void:
	if not enemy_scene:
		push_warning("Enemy scene not loaded")
		return
	
	var wave_number: int = GameState.current_wave
	
	# Calculate enemy stats with map-aware wave scaling.
	var health: float = 50.0 * (1 + (wave_number * 0.2))
	var speed: float = 6.0 * (1 + (wave_number * 0.05))
	var map_wave: WaveData = null
	if MapLoader and MapLoader.has_method("get_wave_data"):
		map_wave = MapLoader.get_wave_data(wave_number)
	if map_wave:
		health = map_wave.get_scaled_health(50.0)
		speed = map_wave.get_scaled_speed(6.0)
	
	var spawn_position: Vector3 = _get_grouped_spawn_position()
	
	var enemy: Node3D = enemy_scene.instantiate() as Node3D
	if enemy:
		# Add to tree before writing global transform values.
		var main: Node = get_tree().root.get_node_or_null("Main")
		if main:
			var enemies_parent: Node = main.get_node_or_null("Enemies")
			if enemies_parent:
				enemies_parent.add_child(enemy)
			else:
				main.add_child(enemy)
		else:
			get_tree().root.add_child(enemy)

		enemy.global_position = spawn_position
		if enemy.has_method("set_stats"):
			enemy.set_stats(health, speed)

		_active_enemies.append(enemy)
		
		# Connect to enemy destroyed signal if available
		if enemy.has_signal("destroyed"):
			enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))
		
		enemy_spawned.emit(enemy)


func _get_grouped_spawn_position() -> Vector3:
	# Start a new group when the current one is exhausted.
	if _current_group_remaining <= 0:
		_start_new_spawn_group()

	var slot_index: int = max(_current_group_remaining - 1, 0)
	var side_sign: float = -1.0 if slot_index % 2 == 0 else 1.0
	var lane_index: int = int(floor(float(slot_index + 1) / 2.0))
	var lane_offset: float = float(lane_index) * GROUP_SPREAD * side_sign
	var radial_jitter: float = randf_range(-4.0, 4.0)

	_current_group_remaining -= 1
	return _current_group_center + (_current_group_tangent * lane_offset) + (_current_group_center.normalized() * radial_jitter)


func _start_new_spawn_group() -> void:
	var remaining: int = max(_total_enemies_for_current_wave - _enemies_spawned_this_wave, 1)
	var target_group_size: int = randi_range(GROUP_SIZE_MIN, GROUP_SIZE_MAX)
	_current_group_remaining = mini(target_group_size, remaining)

	# Pick a random angle around the map edge so groups can come from any direction.
	var spawn_angle: float = randf() * TAU
	var outward: Vector3 = Vector3(cos(spawn_angle), 0, sin(spawn_angle))
	_current_group_center = outward * SPAWN_EDGE_RADIUS
	_current_group_tangent = Vector3(-outward.z, 0, outward.x).normalized()


func _on_enemy_destroyed(enemy: Node3D) -> void:
	_active_enemies.erase(enemy)
	enemy_destroyed.emit(enemy)
	
	# Reward player
	GameState.add_minerals(10)


## Get list of active enemies
var active_enemies: Array[Node3D]:
	get:
		return _active_enemies


## Reset the enemy manager
func reset() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()
	_enemies_spawned_this_wave = 0
	_spawn_timer = 0.0
	_first_wave_started = false
	_current_spawn_delay = SPAWN_DELAY
	_current_group_remaining = 0
	_current_group_center = Vector3.ZERO
	_current_group_tangent = Vector3.RIGHT


func apply_map_wave_settings(map_data: MapData) -> void:
	if not map_data:
		return
	_total_enemies_for_current_wave = _get_enemies_for_wave(0)
	_current_spawn_delay = SPAWN_DELAY
	_spawn_timer = 0.0
	_enemies_spawned_this_wave = 0


## Get all targetable structures for enemies
func get_player_structures() -> Array[Node3D]:
	var structures: Array[Node3D] = []
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main:
		for child in main.get_children():
			if child.has_method("get_team") and child.get_team() == "player":
				structures.append(child)
	return structures
