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

var _active_enemies: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _enemies_spawned_this_wave: int = 0
var _total_enemies_for_current_wave: int = BASE_ENEMIES_PER_WAVE
var _first_wave_started: bool = false

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
		
		if _spawn_timer >= SPAWN_DELAY and _enemies_spawned_this_wave < _total_enemies_for_current_wave:
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
	_total_enemies_for_current_wave = _get_enemies_for_wave(wave_number)
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
	
	# Calculate enemy stats with wave scaling
	var health: float = 50.0 * (1 + (wave_number * 0.2))
	var speed: float = 2.0 * (1 + (wave_number * 0.05))  # Slow enemies (20% of original)
	
	# Randomize spawn position along edge of play area
	var spawn_x: float = randf_range(-100, 100)  # Spawn near play area
	var spawn_position: Vector3 = Vector3(spawn_x, 0, -150)  # Spawn from north edge
	
	var enemy: Node3D = enemy_scene.instantiate() as Node3D
	if enemy:
		enemy.global_position = spawn_position
		if enemy.has_method("set_stats"):
			enemy.set_stats(health, speed)
		
		# Add to Enemies parent node
		var main: Node = get_tree().root.get_node_or_null("Main")
		if main:
			var enemies_parent: Node = main.get_node_or_null("Enemies")
			if enemies_parent:
				enemies_parent.add_child(enemy)
			else:
				main.add_child(enemy)
		else:
			get_tree().root.add_child(enemy)
		_active_enemies.append(enemy)
		
		# Connect to enemy destroyed signal if available
		if enemy.has_signal("destroyed"):
			enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))
		
		enemy_spawned.emit(enemy)


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


## Get all targetable structures for enemies
func get_player_structures() -> Array[Node3D]:
	var structures: Array[Node3D] = []
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main:
		for child in main.get_children():
			if child.has_method("get_team") and child.get_team() == "player":
				structures.append(child)
	return structures
