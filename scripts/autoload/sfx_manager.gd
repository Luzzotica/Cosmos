extends Node
## Global one-shot SFX manager with simple polyphony and event helpers.

const SFX_VOLUME_DB: float = -6.0
const UI_VOLUME_DB: float = -10.0
const MAX_PLAYERS: int = 20
const UI_HOVER_COOLDOWN_MS: int = 90

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0
var _last_ui_hover_ms: int = -10000
var _ignore_power_events_until_ms: int = 0


func _ready() -> void:
	_preload_streams()
	_create_player_pool()
	_ignore_power_events_until_ms = Time.get_ticks_msec() + 1000
	_connect_global_events()


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
		"ui_hover": load("res://assets/generated/audio/sfx/ui_hover.mp3")
	}


func _create_player_pool() -> void:
	for i in range(MAX_PLAYERS):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func _connect_global_events() -> void:
	BuildManager.build_completed.connect(_on_build_completed)
	BuildManager.build_cancelled.connect(_on_build_cancelled)
	SelectionManager.primary_selection_changed.connect(_on_primary_selection_changed)
	PowerGraphManager.node_removed.connect(_on_power_node_removed)


func _on_build_completed(_building_type: String, _position: Vector3) -> void:
	play_sfx("structure_place", SFX_VOLUME_DB)


func _on_build_cancelled() -> void:
	play_sfx("structure_invalid_place", SFX_VOLUME_DB - 2.0)


func _on_primary_selection_changed(_selectable: Node, _details: Dictionary) -> void:
	play_ui_select()


func _on_power_node_removed(_node: Node3D) -> void:
	if Time.get_ticks_msec() < _ignore_power_events_until_ms:
		return
	play_sfx("power_disconnect", SFX_VOLUME_DB - 1.0)
