extends Control
class_name UGCBrowserPanel
## Lightweight in-game browser for approved community maps.

const TOGGLE_KEY: Key = KEY_F8

@onready var refresh_button: Button = $Panel/Margin/VBox/ButtonRow/RefreshButton
@onready var load_button: Button = $Panel/Margin/VBox/ButtonRow/LoadButton
@onready var search_input: LineEdit = $Panel/Margin/VBox/SearchInput
@onready var maps_list: ItemList = $Panel/Margin/VBox/MapsList
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel

var _maps: Array = []


func _ready() -> void:
	visible = false
	refresh_button.pressed.connect(_refresh)
	load_button.pressed.connect(_load_selected_map)
	var ugc_client: Node = get_node_or_null("/root/UGCClient")
	if ugc_client:
		ugc_client.discover_completed.connect(_on_discover_completed)
		ugc_client.download_completed.connect(_on_download_completed)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEY:
			visible = not visible
			if visible:
				_refresh()
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	status_label.text = "Loading approved maps..."
	var search: String = search_input.text.strip_edges()
	var ugc_client: Node = get_node_or_null("/root/UGCClient")
	if ugc_client:
		ugc_client.discover_maps(30, 0, search)
	else:
		status_label.text = "UGC client unavailable."


func _on_discover_completed(success: bool, maps: Array) -> void:
	maps_list.clear()
	_maps = maps
	if not success:
		status_label.text = "Failed to fetch maps."
		return
	for map_item in maps:
		var row: Dictionary = map_item as Dictionary
		var line: String = "%s  (rating %.2f, plays %d)" % [
			String(row.get("title", "Untitled")),
			float(row.get("avg_rating", 0.0)),
			int(row.get("play_count", 0))
		]
		maps_list.add_item(line)
	status_label.text = "Loaded %d map(s)." % maps.size()


func _load_selected_map() -> void:
	var selected: PackedInt32Array = maps_list.get_selected_items()
	if selected.is_empty():
		status_label.text = "Select a map first."
		return
	var index: int = selected[0]
	if index < 0 or index >= _maps.size():
		status_label.text = "Invalid selection."
		return
	var row: Dictionary = _maps[index] as Dictionary
	var map_id: String = String(row.get("id", ""))
	if map_id.is_empty():
		status_label.text = "Map id missing."
		return
	status_label.text = "Downloading map..."
	var ugc_client: Node = get_node_or_null("/root/UGCClient")
	if ugc_client:
		ugc_client.download_and_load_map(map_id)
	else:
		status_label.text = "UGC client unavailable."


func _on_download_completed(success: bool, _map_data: Variant, message: String) -> void:
	status_label.text = "Map loaded." if success else "Load failed: %s" % message
