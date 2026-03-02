extends Node
class_name MapTelemetryClass
## Captures map-related events for moderation/quality operations.

@export var telemetry_enabled: bool = true


func _ready() -> void:
	if MapLoader:
		MapLoader.map_load_failed.connect(_on_map_load_failed)
		MapLoader.map_loaded.connect(_on_map_loaded)
	if GameState:
		GameState.game_over.connect(_on_game_over)


func track_event(event_name: String, payload: Dictionary = {}) -> void:
	if not telemetry_enabled:
		return
	var ugc_client: Node = get_node_or_null("/root/UGCClient")
	if ugc_client == null:
		return
	if ugc_client.supabase_url.is_empty() or ugc_client.supabase_anon_key.is_empty():
		return
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var headers: PackedStringArray = PackedStringArray([
		"apikey: %s" % ugc_client.supabase_anon_key,
		"Content-Type: application/json"
	])
	var body: Dictionary = {
		"event_name": event_name,
		"payload": payload
	}
	var url: String = "%s/functions/v1/track-map-event" % ugc_client.supabase_url.rstrip("/")
	var err: Error = req.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return
	req.request_completed.connect(func(_result: int, _response_code: int, _resp_headers: PackedStringArray, _body: PackedByteArray) -> void:
		req.queue_free()
	)


func _on_map_loaded(map_data: MapData) -> void:
	track_event("map_loaded", {"map_id": map_data.map_id, "name": map_data.map_name})


func _on_map_load_failed(errors: PackedStringArray) -> void:
	track_event("map_load_failed", {"errors": Array(errors)})


func _on_game_over() -> void:
	var current_map_id: String = ""
	if MapLoader and MapLoader.current_map:
		current_map_id = MapLoader.current_map.map_id
	track_event(
		"map_run_finished",
		{
			"map_id": current_map_id,
			"wave_reached": GameState.current_wave,
			"minerals_remaining": GameState.minerals
		}
	)
