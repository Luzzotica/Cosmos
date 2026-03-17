extends Node
## Global music playback and transitions.

enum TrackId {
	BUILD,
	COMBAT_LIGHT,
	COMBAT_HEAVY
}

const CROSSFADE_SECONDS: float = 2.5
const STING_CROSSFADE_SECONDS: float = 1.2
const MUSIC_VOLUME_DB: float = -8.0
const SILENCE_DB: float = -80.0

const TRACK_BUILD: String = "res://assets/audio/music/main_loop_build.mp3"
const TRACK_COMBAT_LIGHT: String = "res://assets/generated/audio/music/combat_loop_light.mp3"
const TRACK_COMBAT_HEAVY: String = "res://assets/generated/audio/music/combat_loop_heavy.mp3"
const STING_VICTORY: String = "res://assets/generated/audio/music/victory_sting.mp3"
const STING_DEFEAT: String = "res://assets/generated/audio/music/defeat_sting.mp3"

var _players: Array[AudioStreamPlayer] = []
var _active_player_index: int = 0
var _crossfade_tween: Tween = null
var _current_track: TrackId = TrackId.BUILD
var _combat_intensity_threshold_wave: int = 3
var _stopped_for_sting: bool = false


func _ready() -> void:
	_create_music_players()
	_connect_game_signals()
	play_build_music(true)


func play_build_music(immediate: bool = false) -> void:
	_stopped_for_sting = false
	_transition_to_track(TrackId.BUILD, immediate)


func play_combat_music(wave_number: int = 0, immediate: bool = false) -> void:
	_stopped_for_sting = false
	var target_track: TrackId = TrackId.COMBAT_LIGHT
	if wave_number >= _combat_intensity_threshold_wave:
		target_track = TrackId.COMBAT_HEAVY
	_transition_to_track(target_track, immediate)


func play_victory_sting() -> void:
	_play_sting(STING_VICTORY)


func play_defeat_sting() -> void:
	_play_sting(STING_DEFEAT)


func _connect_game_signals() -> void:
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)
	GameState.game_over.connect(_on_defeat)
	GameState.victory.connect(_on_victory)


func _on_victory() -> void:
	play_victory_sting()


func _on_defeat() -> void:
	if not GameState.is_victory:
		play_defeat_sting()


func _on_wave_started(wave_number: int) -> void:
	play_combat_music(wave_number, false)


func _on_wave_ended(_wave_number: int) -> void:
	play_build_music(false)


func _create_music_players() -> void:
	for i in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % i
		player.bus = &"Master"
		player.volume_db = SILENCE_DB
		player.finished.connect(_on_player_finished.bind(i))
		add_child(player)
		_players.append(player)


func _transition_to_track(track: TrackId, immediate: bool) -> void:
	if _players.is_empty():
		return
	if _current_track == track and _players[_active_player_index].playing:
		return

	var incoming_stream: AudioStream = _load_looping_track(track)
	if incoming_stream == null:
		return

	var outgoing_idx: int = _active_player_index
	var incoming_idx: int = 1 - outgoing_idx
	var outgoing: AudioStreamPlayer = _players[outgoing_idx]
	var incoming: AudioStreamPlayer = _players[incoming_idx]

	if _crossfade_tween:
		_crossfade_tween.kill()
		_crossfade_tween = null

	incoming.stream = incoming_stream
	incoming.volume_db = MUSIC_VOLUME_DB if immediate else SILENCE_DB
	incoming.play()

	if immediate:
		outgoing.volume_db = SILENCE_DB
		outgoing.stop()
	else:
		# Fade out current track and fade in new track over the same duration.
		outgoing.volume_db = MUSIC_VOLUME_DB
		_crossfade_tween = create_tween().set_parallel(true)
		_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
		_crossfade_tween.set_trans(Tween.TRANS_SINE)
		_crossfade_tween.tween_property(outgoing, "volume_db", SILENCE_DB, CROSSFADE_SECONDS)
		_crossfade_tween.tween_property(incoming, "volume_db", MUSIC_VOLUME_DB, CROSSFADE_SECONDS)
		_crossfade_tween.chain().tween_callback(func() -> void:
			outgoing.stop()
			outgoing.volume_db = SILENCE_DB
			_crossfade_tween = null
		)
		_crossfade_tween.play()

	_active_player_index = incoming_idx
	_current_track = track


func _on_player_finished(player_index: int) -> void:
	if player_index != _active_player_index:
		return
	if _stopped_for_sting:
		return

	var active_player: AudioStreamPlayer = _players[_active_player_index]
	if active_player.stream == null:
		return

	# Guard against stream types that ignore built-in loop flags.
	active_player.play()


func _load_looping_track(track: TrackId) -> AudioStream:
	var path: String = ""
	match track:
		TrackId.BUILD:
			path = TRACK_BUILD
		TrackId.COMBAT_LIGHT:
			path = TRACK_COMBAT_LIGHT
		TrackId.COMBAT_HEAVY:
			path = TRACK_COMBAT_HEAVY

	var stream: AudioStream = load(path) as AudioStream
	return _prepare_looping_stream(stream)


func _prepare_looping_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null

	var copy: AudioStream = stream.duplicate(true)
	if copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	return copy


func _play_sting(path: String) -> void:
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return

	if _crossfade_tween:
		_crossfade_tween.kill()
		_crossfade_tween = null

	var outgoing_idx: int = _active_player_index
	var incoming_idx: int = 1 - outgoing_idx
	var outgoing: AudioStreamPlayer = _players[outgoing_idx]
	var incoming: AudioStreamPlayer = _players[incoming_idx]

	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()

	_crossfade_tween = create_tween().set_parallel(true)
	_crossfade_tween.set_ease(Tween.EASE_IN_OUT)
	_crossfade_tween.set_trans(Tween.TRANS_SINE)
	_crossfade_tween.tween_property(outgoing, "volume_db", SILENCE_DB, STING_CROSSFADE_SECONDS)
	_crossfade_tween.tween_property(incoming, "volume_db", MUSIC_VOLUME_DB + 1.5, STING_CROSSFADE_SECONDS)
	_crossfade_tween.chain().tween_callback(func() -> void:
		outgoing.stop()
		outgoing.volume_db = SILENCE_DB
		_crossfade_tween = null
	)
	_crossfade_tween.play()

	_active_player_index = incoming_idx
	_stopped_for_sting = true
