extends Node3D
class_name MainMenu
## Unified main menu with pan-to-level-area, zoom on select, and save slot selection.
## Level detail shows as a 3D hologram billboard floating above the selected node.

enum State { HOME, LEVEL_SELECT, LEVEL_DETAIL }

const CAMERA_HOME_POS: Vector3 = Vector3(6.07, 12.87, 7.65)
const CAMERA_HOME_ROT: Vector3 = Vector3(-1.047, 0, 0)
const PAN_DURATION: float = 1.2
const LEFT_FADE_DURATION: float = 0.6
const ZOOM_DURATION: float = 0.8
const BILLBOARD_SHOW_DELAY: float = 0.4
const ZOOM_OFFSET: Vector3 = Vector3(0, 2.0, 1.2)
const BILLBOARD_HEIGHT: float = 0.8
const PARALLAX_MAX_YAW: float = 0.0523599 / 8.0 ## ~3/8 deg
const PARALLAX_MAX_PITCH: float = 0.0523599 / 8.0 ## ~3/8 deg
const PARALLAX_SMOOTH: float = 12.0

var _state: State = State.HOME
var _parallax_yaw: float = 0.0
var _parallax_pitch: float = 0.0
var _selected_slot: int = 1
var _entries: Array[Dictionary] = []
var _selected_entry: Dictionary = {}
var _level_nodes: Array[Node] = []
var _last_hovered_node: Node = null
var _left_container_width: float = 450.0
var _selected_node: Node = null

@onready var camera_rig: Node3D = $MainMenuWorld/CameraRig
@onready var camera: Camera3D = $MainMenuWorld/CameraRig/Camera3D
@onready var camera_target: Node3D = $CameraTarget
@onready var left_ui_container: Control = $UILayer/LeftUIContainer
@onready var billboard: Node3D = $HoloBillboard/HoloBillboard3D
@onready var level_nodes_parent: Node3D = $LevelArea/LevelNodes
@onready var story_levels_button: Button = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/StoryLevelsButton
@onready var new_game_button: Button = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/NewGameButton
@onready var quit_button: Button = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/QuitButton
@onready var slot_buttons: Array[Button] = [
	$UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/SlotPicker/Slot1,
	$UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/SlotPicker/Slot2,
	$UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/SlotPicker/Slot3
]
@onready var level_select_back: Control = $UILayer/LevelSelectBack
@onready var back_to_menu_button: Button = $UILayer/LevelSelectBack/BackToMenuButton


func _ready() -> void:
	MusicManager.play_build_music(true)
	story_levels_button.pressed.connect(_on_story_levels_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	billboard.set_camera(camera)
	billboard.back_pressed.connect(_on_back_pressed)
	billboard.launch_pressed.connect(_on_launch_pressed)
	for i in slot_buttons.size():
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))
	_build_entries()
	_update_slot_ui()
	SaveManager.set_current_slot(_selected_slot)
	await get_tree().process_frame
	_left_container_width = left_ui_container.size.x


func _process(delta: float) -> void:
	_update_camera_parallax(delta)
	if _state == State.LEVEL_SELECT:
		_sync_level_node_hover()


func _update_camera_parallax(delta: float) -> void:
	var target_yaw: float = 0.0
	var target_pitch: float = 0.0
	if _state in [State.LEVEL_SELECT, State.LEVEL_DETAIL]:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		if vp.x > 0.0 and vp.y > 0.0:
			var m: Vector2 = get_viewport().get_mouse_position()
			var nx: float = (m.x / vp.x) * 2.0 - 1.0
			var ny: float = (m.y / vp.y) * 2.0 - 1.0
			target_yaw = -nx * PARALLAX_MAX_YAW
			target_pitch = -ny * PARALLAX_MAX_PITCH
	var k: float = 1.0 - exp(-PARALLAX_SMOOTH * delta)
	_parallax_yaw = lerp_angle(_parallax_yaw, target_yaw, k)
	_parallax_pitch = lerp_angle(_parallax_pitch, target_pitch, k)
	camera.rotation = Vector3(_parallax_pitch, _parallax_yaw, 0.0)


func _input(event: InputEvent) -> void:
	if _state != State.LEVEL_SELECT:
		return
	if event is InputEventMouseMotion:
		_update_hover_at_screen_pos((event as InputEventMouseMotion).position)


func _sync_level_node_hover() -> void:
	_update_hover_at_screen_pos(get_viewport().get_mouse_position())


func _update_hover_at_screen_pos(screen_pos: Vector2) -> void:
	var hit: Node = _raycast_level_node(screen_pos)
	if _last_hovered_node != hit:
		if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
			_last_hovered_node.set_hovered(false)
		_last_hovered_node = hit
		if hit and hit.has_method("set_hovered"):
			hit.set_hovered(true)


func _raycast_level_node(screen_pos: Vector2) -> Node:
	var viewport: Viewport = get_viewport()
	var cam: Camera3D = viewport.get_camera_3d()
	if not cam:
		return null
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var to: Vector3 = from + dir * 500.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return null
	var collider: Object = result.get("collider", null)
	if collider is Area3D and collider.has_method("setup"):
		return collider
	return null


func _build_entries() -> void:
	_entries.clear()
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager == null:
		return
	var manifest: Dictionary = story_manager.manifest
	var ordered: Array = manifest.get("ordered_map_ids", [])
	var maps: Array = manifest.get("maps", [])
	for map_id in ordered:
		var entry: Dictionary = _get_entry_by_id(maps, map_id)
		if not entry.is_empty():
			_entries.append(entry)


func _get_entry_by_id(maps: Array, map_id: String) -> Dictionary:
	for entry_variant in maps:
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			if String(entry.get("id", "")) == map_id:
				return entry
	return {}


func _update_slot_ui() -> void:
	for i in slot_buttons.size():
		var slot: int = i + 1
		var info: Dictionary = SaveManager.get_slot_info(slot)
		var label: String = "Slot %d" % slot
		if info.get("exists", false):
			label += "\n" + info.get("preview_text", "")
		slot_buttons[i].text = label
		slot_buttons[i].button_pressed = (slot == _selected_slot)


func _on_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	SaveManager.set_current_slot(slot)
	_update_slot_ui()
	_play_sfx("play_ui_confirm")


func _on_story_levels_pressed() -> void:
	SaveManager.set_current_slot(_selected_slot)
	_state = State.LEVEL_SELECT
	_selected_entry = {}
	_selected_node = null
	_configure_level_nodes()
	_pan_camera_to_level()
	_fade_left_out()
	level_select_back.visible = true
	_play_sfx("play_ui_confirm")


func _configure_level_nodes() -> void:
	_level_nodes.clear()
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var maps: Array = StoryCampaignManager.manifest.get("maps", [])
	for child in level_nodes_parent.get_children():
		if not child.has_method("setup"):
			continue
		var map_id_val: Variant = child.get("map_id")
		if map_id_val == null:
			continue
		var map_id: String = String(map_id_val)
		if map_id.is_empty():
			continue
		var entry: Dictionary = _get_entry_by_id(maps, map_id)
		if entry.is_empty():
			continue
		var unlocked: bool = true
		if save_manager and save_manager.has_method("is_level_unlocked"):
			unlocked = save_manager.call("is_level_unlocked", map_id)
		var beaten: bool = false
		if save_manager and save_manager.has_method("is_level_beaten"):
			beaten = save_manager.call("is_level_beaten", map_id)
		child.setup(entry, unlocked, beaten)
		if child.has_signal("selected"):
			child.selected.connect(_on_level_node_selected)
		_level_nodes.append(child)


func _find_node_for_entry(entry: Dictionary) -> Node:
	var map_id: String = String(entry.get("id", ""))
	for node in _level_nodes:
		if String(node.entry.get("id", "")) == map_id:
			return node
	return null


func _on_level_node_selected(entry: Dictionary) -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var map_id: String = String(entry.get("id", ""))
	var unlocked: bool = true
	if save_manager and save_manager.has_method("is_level_unlocked"):
		unlocked = save_manager.call("is_level_unlocked", map_id)
	if not unlocked:
		return
	if _state == State.LEVEL_SELECT:
		_selected_entry = entry
		var node: Node = _find_node_for_entry(entry)
		if node:
			_transition_to_level_detail(node)
	_play_sfx("play_ui_confirm")


func _transition_to_level_detail(node: Node) -> void:
	if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
		_last_hovered_node.set_hovered(false)
	_last_hovered_node = null
	_state = State.LEVEL_DETAIL
	_selected_node = node
	level_select_back.visible = false

	var map_id: String = String(_selected_entry.get("id", ""))
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var unlocked: bool = true
	if save_manager and save_manager.has_method("is_level_unlocked"):
		unlocked = save_manager.call("is_level_unlocked", map_id)
	billboard.set_content(_short_label(_selected_entry), _get_description(_selected_entry), unlocked)
	billboard.global_position = node.global_position + Vector3(0, BILLBOARD_HEIGHT, 0)

	if node.has_method("set_rotation_focused"):
		node.call("set_rotation_focused", true)

	_zoom_camera_to_node(node)
	_show_billboard_delayed()


func _get_description(entry: Dictionary) -> String:
	var desc: String = String(entry.get("description", ""))
	if not desc.is_empty():
		return desc
	return _short_label(entry)


func _short_label(entry: Dictionary) -> String:
	var chapter: String = String(entry.get("chapter", ""))
	if chapter.begins_with("chapter_"):
		chapter = chapter.trim_prefix("chapter_")
	return chapter


# --- Left panel animations ---

func _fade_left_out() -> void:
	left_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(left_ui_container, "position:x", -_left_container_width, LEFT_FADE_DURATION)
	tween.parallel().tween_property(left_ui_container, "modulate", Color(1, 1, 1, 0), LEFT_FADE_DURATION)


func _fade_left_in() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(left_ui_container, "position:x", 0.0, LEFT_FADE_DURATION)
	tween.parallel().tween_property(left_ui_container, "modulate", Color(1, 1, 1, 1), LEFT_FADE_DURATION)
	tween.tween_callback(func(): left_ui_container.mouse_filter = Control.MOUSE_FILTER_STOP)


# --- Billboard show/hide ---

func _show_billboard_delayed() -> void:
	var tween: Tween = create_tween()
	tween.tween_interval(BILLBOARD_SHOW_DELAY)
	tween.tween_callback(func(): billboard.show_billboard())


# --- Camera animations ---

func _zoom_camera_to_node(node: Node) -> void:
	var node_pos: Vector3 = node.global_position
	var zoom_pos: Vector3 = node_pos + ZOOM_OFFSET
	var target_transform: Transform3D = Transform3D()
	target_transform.origin = zoom_pos
	target_transform = target_transform.looking_at(node_pos, Vector3.UP)
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_transform", target_transform, ZOOM_DURATION)


func _zoom_camera_out() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_position", camera_target.global_position, ZOOM_DURATION)
	tween.parallel().tween_property(camera_rig, "global_rotation", camera_target.global_rotation, ZOOM_DURATION)


func _pan_camera_to_level() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_position", camera_target.global_position, PAN_DURATION)
	tween.parallel().tween_property(camera_rig, "global_rotation", camera_target.global_rotation, PAN_DURATION)


func _pan_camera_home() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_position", CAMERA_HOME_POS, PAN_DURATION)
	tween.parallel().tween_property(camera_rig, "rotation", CAMERA_HOME_ROT, PAN_DURATION)


# --- Button handlers ---

func _on_back_to_menu_pressed() -> void:
	_on_back_from_level_select()


func _on_back_pressed() -> void:
	if _state == State.LEVEL_DETAIL:
		if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
			_last_hovered_node.set_hovered(false)
			_last_hovered_node = null
		var prev_selected: Node = _selected_node
		if prev_selected and prev_selected.has_method("set_rotation_focused"):
			prev_selected.call("set_rotation_focused", false)
		_state = State.LEVEL_SELECT
		_selected_entry = {}
		_selected_node = null
		level_select_back.visible = true
		billboard.hide_billboard(func(): _zoom_camera_out())
		_play_sfx("play_ui_confirm")
	elif _state == State.LEVEL_SELECT:
		_on_back_from_level_select()


func _on_back_from_level_select() -> void:
	if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
		_last_hovered_node.set_hovered(false)
		_last_hovered_node = null
	level_select_back.visible = false
	_state = State.HOME
	_pan_camera_home()
	_fade_left_in()
	_play_sfx("play_ui_confirm")


func _on_launch_pressed() -> void:
	if _selected_entry.is_empty():
		return
	var map_path: String = String(_selected_entry.get("map_path", ""))
	var map_id: String = String(_selected_entry.get("id", ""))
	if map_path.is_empty():
		return
	var session: Node = get_node_or_null("/root/GameSession")
	if session and session.has_method("start_story"):
		session.call("start_story", map_path, map_id)
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager and story_manager.has_method("set_current_by_map_id"):
		story_manager.call("set_current_by_map_id", map_id)
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")
	_play_sfx("play_ui_confirm")


func _on_new_game_pressed() -> void:
	var info: Dictionary = SaveManager.get_slot_info(_selected_slot)
	if info.get("exists", false):
		# TODO: confirm overwrite dialog; for now just overwrite
		pass
	SaveManager.create_new_slot(_selected_slot)
	_update_slot_ui()
	_play_sfx("play_ui_confirm")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _play_sfx(method_name: String) -> void:
	var sfx: Node = get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method(method_name):
		sfx.call(method_name)
