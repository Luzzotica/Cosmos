extends Node
## EnemyManager Singleton - Manages enemy spawning and tactical coordination.

signal enemy_spawned(enemy: Node3D)
signal enemy_destroyed(enemy: Node3D)
signal wave_started(wave_number: int, total_enemies: int)
signal wave_completed(wave_number: int)

const EnemyBlackboardClass: Script = preload("res://scripts/enemies/enemy_blackboard.gd")

const BASE_ENEMIES_PER_WAVE: int = 3
const SPAWN_DELAY: float = 2.0
const SPAWN_EDGE_RADIUS: float = 170.0
const GROUP_SIZE_MIN: int = 2
const GROUP_SIZE_MAX: int = 4
const GROUP_SPREAD: float = 16.0
const DEFAULT_ENEMY_ID: String = "enemy_standard"
const COMMANDER_PERIOD: int = 3

var _active_enemies: Array[Node3D] = []
var _spawn_timer: float = 0.0
var _enemies_spawned_this_wave: int = 0
var _total_enemies_for_current_wave: int = BASE_ENEMIES_PER_WAVE
var _current_group_remaining: int = 0
var _current_group_center: Vector3 = Vector3.ZERO
var _current_group_tangent: Vector3 = Vector3.RIGHT
var _current_spawn_delay: float = SPAWN_DELAY
var _spawn_queue: Array[String] = []
var _enemy_data_by_id: Dictionary = {}
var _enemy_scene_cache: Dictionary = {}
var _blackboard: RefCounted = EnemyBlackboardClass.new()
var _commander_auras: Dictionary = {}


func _ready() -> void:
	_load_enemy_registry()
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)
	_schedule_first_wave()


func _schedule_first_wave() -> void:
	pass


func _process(delta: float) -> void:
	if GameState.is_paused or GameState.is_game_over:
		return
	_blackboard.clear_expired()
	_cleanup_commander_auras()
	if not GameState.is_wave_in_progress:
		return

	_spawn_timer += delta
	if _spawn_timer >= _current_spawn_delay and _enemies_spawned_this_wave < _total_enemies_for_current_wave:
		_spawn_enemy()
		_spawn_timer = 0.0
		_enemies_spawned_this_wave += 1

	_active_enemies = _active_enemies.filter(func(e): return is_instance_valid(e) and not e.is_destroyed)
	if _enemies_spawned_this_wave >= _total_enemies_for_current_wave and _active_enemies.is_empty():
		GameState.end_wave()
		_enemies_spawned_this_wave = 0
		wave_completed.emit(GameState.current_wave - 1)


func _on_wave_started(wave_number: int) -> void:
	var map_wave: WaveData = null
	if MapLoader and MapLoader.has_method("get_wave_data"):
		map_wave = MapLoader.get_wave_data(wave_number)

	_build_spawn_queue_for_wave(wave_number, map_wave)
	_total_enemies_for_current_wave = _spawn_queue.size()
	_current_spawn_delay = map_wave.spawn_delay if map_wave else SPAWN_DELAY
	_spawn_timer = 0.0
	_enemies_spawned_this_wave = 0
	wave_started.emit(wave_number, _total_enemies_for_current_wave)


func _on_wave_ended(_wave_number: int) -> void:
	pass


func _get_enemies_for_wave(wave_number: int) -> int:
	return BASE_ENEMIES_PER_WAVE + (wave_number * 2)


func _spawn_enemy() -> void:
	var enemy_id: String = DEFAULT_ENEMY_ID
	if _enemies_spawned_this_wave >= 0 and _enemies_spawned_this_wave < _spawn_queue.size():
		enemy_id = _spawn_queue[_enemies_spawned_this_wave]

	var enemy_data: Resource = _enemy_data_by_id.get(enemy_id, null)
	if enemy_data == null:
		enemy_data = _enemy_data_by_id.get(DEFAULT_ENEMY_ID, null)
	if enemy_data == null:
		push_warning("Enemy data not found for id: %s" % enemy_id)
		return

	var enemy_scene: PackedScene = _get_enemy_scene(enemy_data.scene_path)
	if enemy_scene == null:
		push_warning("Enemy scene not loaded for id: %s" % enemy_id)
		return

	var wave_number: int = GameState.current_wave
	var health_multiplier: float = 1.0 + (wave_number * 0.2)
	var speed_multiplier: float = 1.0 + (wave_number * 0.05)
	var map_wave: WaveData = null
	if MapLoader and MapLoader.has_method("get_wave_data"):
		map_wave = MapLoader.get_wave_data(wave_number)
	if map_wave:
		health_multiplier = map_wave.enemy_health_multiplier
		speed_multiplier = map_wave.enemy_speed_multiplier

	var spawn_position: Vector3 = _get_grouped_spawn_position()
	var enemy: Node3D = enemy_scene.instantiate() as Node3D
	if enemy == null:
		return

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
	if enemy.has_method("set_enemy_data"):
		enemy.set_enemy_data(enemy_data, health_multiplier, speed_multiplier)
	elif enemy.has_method("set_stats"):
		enemy.set_stats(enemy_data.max_health * health_multiplier, enemy_data.speed * speed_multiplier)

	_active_enemies.append(enemy)
	if enemy.has_signal("destroyed"):
		enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))
	enemy_spawned.emit(enemy)


func _get_grouped_spawn_position() -> Vector3:
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
	var spawn_angle: float = randf() * TAU
	var outward: Vector3 = Vector3(cos(spawn_angle), 0, sin(spawn_angle))
	_current_group_center = outward * SPAWN_EDGE_RADIUS
	_current_group_tangent = Vector3(-outward.z, 0, outward.x).normalized()


func _on_enemy_destroyed(enemy: Node3D) -> void:
	_active_enemies.erase(enemy)
	_blackboard.clear_enemy(enemy)
	enemy_destroyed.emit(enemy)


var active_enemies: Array[Node3D]:
	get:
		return _active_enemies


func reset() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()
	_enemies_spawned_this_wave = 0
	_spawn_timer = 0.0
	_current_spawn_delay = SPAWN_DELAY
	_current_group_remaining = 0
	_current_group_center = Vector3.ZERO
	_current_group_tangent = Vector3.RIGHT
	_spawn_queue.clear()
	_commander_auras.clear()
	_blackboard = EnemyBlackboardClass.new()


func apply_map_wave_settings(map_data: MapData) -> void:
	if not map_data:
		return
	_total_enemies_for_current_wave = _get_enemies_for_wave(0)
	_current_spawn_delay = SPAWN_DELAY
	_spawn_timer = 0.0
	_enemies_spawned_this_wave = 0
	_spawn_queue.clear()


func register_commander_aura(commander: Node3D, aura_data: Dictionary) -> void:
	if commander == null:
		return
	_commander_auras[commander.get_instance_id()] = {
		"commander": commander,
		"data": aura_data
	}


func get_tactical_modifier_for_enemy(enemy: Node3D) -> Dictionary:
	var modifier: Dictionary = _blackboard.get_enemy_modifier(enemy)
	if not modifier.is_empty():
		return modifier

	var merged: Dictionary = {}
	for aura_entry in _commander_auras.values():
		var commander: Node3D = aura_entry.get("commander", null)
		if commander == null or not is_instance_valid(commander) or commander == enemy:
			continue
		if commander.get("is_destroyed") == true:
			continue
		var aura_data: Dictionary = aura_entry.get("data", {})
		var radius: float = float(aura_data.get("radius", 0.0))
		if radius <= 0.0:
			continue
		if enemy.global_position.distance_to(commander.global_position) > radius:
			continue
		_merge_tactical_modifier(merged, aura_data)

	if not merged.is_empty():
		_blackboard.set_enemy_modifier(enemy, merged, 0.35)
	return merged


func clear_enemy_from_blackboard(enemy: Node3D) -> void:
	_blackboard.clear_enemy(enemy)
	if enemy != null:
		_commander_auras.erase(enemy.get_instance_id())


func get_player_structures() -> Array[Node3D]:
	var structures: Array[Node3D] = []
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return structures
	var structures_parent: Node = main.get_node_or_null("Structures")
	if not structures_parent:
		return structures
	for child in structures_parent.get_children():
		if child is BaseStructure and not child.is_destroyed:
			structures.append(child)
	return structures


func _load_enemy_registry() -> void:
	var registry_paths: Dictionary = {
		"enemy_standard": "res://resources/enemies/enemy_standard.tres",
		"enemy_laser_immune": "res://resources/enemies/enemy_laser_immune.tres",
		"enemy_physical_immune": "res://resources/enemies/enemy_physical_immune.tres",
		"enemy_saboteur": "res://resources/enemies/enemy_saboteur.tres",
		"enemy_commander": "res://resources/enemies/enemy_commander.tres"
	}
	for enemy_id in registry_paths.keys():
		var path: String = registry_paths[enemy_id]
		if not ResourceLoader.exists(path):
			continue
		var data: Resource = load(path)
		if data != null:
			_enemy_data_by_id[enemy_id] = data


func _build_spawn_queue_for_wave(wave_number: int, wave_data: WaveData) -> void:
	_spawn_queue.clear()
	if wave_data and not wave_data.enemy_composition.is_empty():
		for entry in wave_data.enemy_composition:
			if entry == null:
				continue
			var count: int = maxi(int(entry.get("count")), 0)
			var enemy_id: String = String(entry.get("enemy_id"))
			for _i in range(count):
				_spawn_queue.append(enemy_id)
		_spawn_queue.shuffle()
		return

	var fallback_total: int = _get_enemies_for_wave(wave_number)
	if wave_data:
		fallback_total = maxi(wave_data.enemy_count, 0)
	for _i in range(fallback_total):
		_spawn_queue.append(DEFAULT_ENEMY_ID)

	if wave_number >= COMMANDER_PERIOD and wave_number % COMMANDER_PERIOD == 0 and not _spawn_queue.is_empty():
		_spawn_queue[_spawn_queue.size() - 1] = "enemy_commander"
	if wave_number >= 2 and _spawn_queue.size() >= 2:
		_spawn_queue[0] = "enemy_saboteur"
	if wave_number >= 3 and _spawn_queue.size() >= 3:
		_spawn_queue[1] = "enemy_laser_immune"
	if wave_number >= 4 and _spawn_queue.size() >= 4:
		_spawn_queue[2] = "enemy_physical_immune"


func _get_enemy_scene(scene_path: String) -> PackedScene:
	if _enemy_scene_cache.has(scene_path):
		return _enemy_scene_cache[scene_path]
	if not ResourceLoader.exists(scene_path):
		return null
	var loaded_scene: PackedScene = load(scene_path)
	if loaded_scene:
		_enemy_scene_cache[scene_path] = loaded_scene
	return loaded_scene


func _cleanup_commander_auras() -> void:
	var stale_ids: Array = []
	for commander_id in _commander_auras.keys():
		var commander: Node3D = _commander_auras[commander_id].get("commander", null)
		if commander == null or not is_instance_valid(commander) or commander.get("is_destroyed") == true:
			stale_ids.append(commander_id)
	for stale_id in stale_ids:
		_commander_auras.erase(stale_id)


func _merge_tactical_modifier(current: Dictionary, incoming: Dictionary) -> void:
	var multiplicative_keys: Array[String] = [
		"speed_multiplier",
		"damage_multiplier",
		"attack_cooldown_multiplier",
		"attack_range_multiplier",
		"target_priority_multiplier"
	]
	for key in multiplicative_keys:
		if incoming.has(key):
			var existing: float = float(current.get(key, 1.0))
			current[key] = existing * float(incoming[key])
	if incoming.has("retarget_interval_override"):
		var existing_interval: float = float(current.get("retarget_interval_override", INF))
		current["retarget_interval_override"] = minf(existing_interval, float(incoming["retarget_interval_override"]))
