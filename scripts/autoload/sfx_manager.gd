extends Node
## Global one-shot SFX manager with simple polyphony and event helpers.
## World SFX use AudioStreamPlayer3D so volume falls off with distance from the camera.

## Nominal level at the emitter for world SFX (3D distance attenuates from here).
const SFX_VOLUME_DB: float = -1.0
const UI_VOLUME_DB: float = -10.0
const MAX_PLAYERS: int = 20
const MAX_PLAYERS_3D: int = 24
const UI_HOVER_COOLDOWN_MS: int = 90
## Beyond this distance from the listener, 3D SFX are fully attenuated (see AudioStreamPlayer3D.max_distance).
const DEFAULT_SFX_MAX_DISTANCE: float = 72.0
const EXPLOSION_SFX_MAX_DISTANCE: float = 96.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_player_index: int = 0
var _next_player_3d_index: int = 0
var _last_ui_hover_ms: int = -10000
var _ignore_power_events_until_ms: int = 0


func _ready() -> void:
	_preload_streams()
	_create_player_pool()
	_create_player_3d_pool()
	_ignore_power_events_until_ms = Time.get_ticks_msec() + 1000
	_connect_global_events()


## Non-positional SFX (UI, menus). Use [method play_sfx_at] for anything that happens in the 3D world.
func play_sfx(id: String, volume_db: float = SFX_VOLUME_DB, pitch_scale: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(id, null) as AudioStream
	if stream == null or _players.is_empty():
		return

	var player: AudioStreamPlayer = _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()

	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


func play_sfx_at(world_position: Vector3, id: String, volume_db: float = SFX_VOLUME_DB, pitch_scale: float = 1.0, max_distance: float = DEFAULT_SFX_MAX_DISTANCE) -> void:
	var stream: AudioStream = _streams.get(id, null) as AudioStream
	if stream == null or _players_3d.is_empty():
		return

	var player: AudioStreamPlayer3D = _players_3d[_next_player_3d_index]
	_next_player_3d_index = (_next_player_3d_index + 1) % _players_3d.size()

	player.stop()
	player.global_position = world_position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = max_distance
	player.play()


func play_ui_select() -> void:
	play_sfx("ui_select", UI_VOLUME_DB)


func play_ui_confirm() -> void:
	play_sfx("ui_confirm", UI_VOLUME_DB)


func play_ui_hover() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_ui_hover_ms < UI_HOVER_COOLDOWN_MS:
		return
	_last_ui_hover_ms = now_ms

	if _streams.has("ui_hover"):
		play_sfx("ui_hover", UI_VOLUME_DB - 1.0)
	else:
		# Fallback so hover feedback still works if ui_hover was not imported yet.
		play_sfx("ui_select", UI_VOLUME_DB - 2.0, 1.08)


func _preload_streams() -> void:
	_streams = {
		"laser_shot": load("res://assets/generated/audio/sfx/laser_shot.mp3"),
		"laser_impact": load("res://assets/generated/audio/sfx/laser_impact.mp3"),
		"structure_place": load("res://assets/generated/audio/sfx/structure_place.mp3"),
		"structure_invalid_place": load("res://assets/generated/audio/sfx/structure_invalid_place.mp3"),
		"mining_pulse": load("res://assets/generated/audio/sfx/mining_pulse.mp3"),
		"power_disconnect": load("res://assets/generated/audio/sfx/power_disconnect.mp3"),
		"ui_select": load("res://assets/generated/audio/sfx/ui_select.mp3"),
		"ui_confirm": load("res://assets/generated/audio/sfx/ui_confirm.mp3"),
		"ui_hover": load("res://assets/generated/audio/sfx/ui_hover.mp3"),
		"missile_launch": load("res://assets/generated/audio/sfx/missile_launch.mp3"),
		"missile_explosion": load("res://assets/generated/audio/sfx/missile_explosion.mp3"),
		"enemy_death": load("res://assets/generated/audio/sfx/enemy_death.mp3"),
		"wave_alert": load("res://assets/generated/audio/sfx/wave_alert.mp3")
	}


func _create_player_pool() -> void:
	for i in range(MAX_PLAYERS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func _create_player_3d_pool() -> void:
	for i in range(MAX_PLAYERS_3D):
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "SfxPlayer3D%d" % i
		player.bus = &"Master"
		add_child(player)
		_players_3d.append(player)


func _connect_global_events() -> void:
	BuildManager.build_completed.connect(_on_build_completed)
	BuildManager.build_cancelled.connect(_on_build_cancelled)
	SelectionManager.primary_selection_changed.connect(_on_primary_selection_changed)
	PowerGraphManager.node_removed.connect(_on_power_node_removed)
	GameState.wave_started.connect(_on_game_wave_started)


func _on_build_completed(_building_type: String, position: Vector3, _building: Node = null) -> void:
	play_sfx_at(position, "structure_place", SFX_VOLUME_DB)


func _on_build_cancelled(at_position: Vector3) -> void:
	play_sfx_at(at_position, "structure_invalid_place", SFX_VOLUME_DB - 2.0)


func _on_primary_selection_changed(_selectable: Node, _details: Dictionary) -> void:
	play_ui_select()


func _on_power_node_removed(_node: Node3D) -> void:
	if Time.get_ticks_msec() < _ignore_power_events_until_ms:
		return
	var pos: Vector3 = _node.global_position if _node and is_instance_valid(_node) else Vector3.ZERO
	play_sfx_at(pos, "power_disconnect", SFX_VOLUME_DB - 1.0)


func _on_game_wave_started(_wave_number: int) -> void:
	play_sfx("wave_alert", -24.0)
