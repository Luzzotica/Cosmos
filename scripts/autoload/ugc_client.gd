extends Node
class_name UGCClientClass
## Supabase-backed online map publishing and discovery client.

const MapValidatorClass: Script = preload("res://scripts/data/map_validator.gd")

signal publish_completed(success: bool, payload: Dictionary)
signal discover_completed(success: bool, maps: Array)
signal download_completed(success: bool, map_data: Variant, message: String)

@export var supabase_url: String = ""
@export var supabase_anon_key: String = ""
@export var supabase_jwt: String = ""


func _ready() -> void:
	if supabase_url.is_empty():
		supabase_url = OS.get_environment("SUPABASE_URL")
	if supabase_anon_key.is_empty():
		supabase_anon_key = OS.get_environment("SUPABASE_ANON_KEY")


func set_auth_token(jwt: String) -> void:
	supabase_jwt = jwt


func publish_map(
	map_data: MapData,
	title: String,
	description: String,
	tags: PackedStringArray = PackedStringArray(),
	map_id: String = ""
) -> void:
	var validation: Dictionary = MapValidatorClass.validate_map_data(map_data)
	if not bool(validation.get("is_valid", false)):
		publish_completed.emit(false, {"error": "Map validation failed", "details": validation.get("errors", [])})
		return

	var body: Dictionary = {
		"map_id": map_id,
		"title": title,
		"description": description,
		"tags": Array(tags),
		"schema_version": map_data.schema_version,
		"payload_json": map_data._to_dict()
	}
	var response: Dictionary = await _request_json("/functions/v1/publish-map", HTTPClient.METHOD_POST, body, true)
	publish_completed.emit(bool(response.get("ok", false)), response)


func discover_maps(limit: int = 20, offset: int = 0, search: String = "") -> void:
	var endpoint: String = "/functions/v1/discover-maps?limit=%d&offset=%d&q=%s" % [limit, offset, search.uri_encode()]
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, {}, false)
	var maps: Array = response.get("maps", [])
	discover_completed.emit(bool(response.get("ok", false)), maps)


func download_and_load_map(map_id: String) -> void:
	var endpoint: String = "/functions/v1/download-map?map_id=%s" % map_id.uri_encode()
	var response: Dictionary = await _request_json(endpoint, HTTPClient.METHOD_GET, {}, false)
	if not bool(response.get("ok", false)):
		download_completed.emit(false, null, String(response.get("error", "download failed")))
		return

	var version_data: Dictionary = response.get("version", {})
	var payload: Dictionary = version_data.get("payload_json", {})
	var strict_result: Dictionary = MapValidatorClass.validate_json_dict(payload)
	if not bool(strict_result.get("is_valid", false)):
		download_completed.emit(false, null, "Downloaded map failed schema checks")
		return

	var map_data: MapData = MapData._create_from_dict(payload)
	MapLoader.load_map(map_data)
	download_completed.emit(true, map_data, "ok")


func _request_json(endpoint: String, method: HTTPClient.Method, body: Dictionary, needs_auth: bool) -> Dictionary:
	if supabase_url.is_empty() or supabase_anon_key.is_empty():
		return {"ok": false, "error": "Missing SUPABASE_URL or SUPABASE_ANON_KEY"}

	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	var headers: PackedStringArray = PackedStringArray([
		"apikey: %s" % supabase_anon_key,
		"Content-Type: application/json"
	])
	if needs_auth:
		if supabase_jwt.is_empty():
			req.queue_free()
			return {"ok": false, "error": "Missing auth token for protected endpoint"}
		headers.append("Authorization: Bearer %s" % supabase_jwt)

	var payload_text: String = JSON.stringify(body) if method != HTTPClient.METHOD_GET else ""
	var err: Error = req.request(
		"%s%s" % [supabase_url.rstrip("/"), endpoint],
		headers,
		method,
		payload_text
	)
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "Network error: %s" % err}

	var result: Array = await req.request_completed
	req.queue_free()
	var response_code: int = int(result[1])
	var raw: PackedByteArray = result[3]
	var as_text: String = raw.get_string_from_utf8()
	var parse: JSON = JSON.new()
	var parse_error: Error = parse.parse(as_text)
	if parse_error != OK:
		return {"ok": false, "error": "Invalid JSON response"}

	var parsed: Dictionary = parse.data if parse.data is Dictionary else {}
	parsed["ok"] = response_code >= 200 and response_code < 300
	return parsed
