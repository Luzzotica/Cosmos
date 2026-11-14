extends Node3D
class_name MainMenu
## Main menu: home (Endless / Quit) and endless difficulty selection (pan camera left).

enum State { HOME, ENDLESS_SELECT, ENDLESS_CONFIRM }

const CAMERA_HOME_POS: Vector3 = Vector3(6.07, 12.87, 7.65)
const CAMERA_HOME_ROT: Vector3 = Vector3(-1.047, 0, 0)
const PAN_DURATION: float = 1.2
const LEFT_FADE_DURATION: float = 0.6
const LEVEL_NODES_FADE_DURATION: float = 0.65
const ENDLESS_ZOOM_DURATION: float = 0.85
## Offset from the selected node's world position to the camera anchor.
## Tweak Y (height above node) and Z (depth toward viewer) to taste.
const ENDLESS_CONFIRM_ANCHOR_OFFSET: Vector3 = Vector3(0.0, 0.325, 0.675)
const PARALLAX_MAX_YAW: float = 0.0523599 / 8.0
const PARALLAX_MAX_PITCH: float = 0.0523599 / 8.0
const PARALLAX_SMOOTH: float = 12.0

var _state: State = State.HOME
var _parallax_yaw: float = 0.0
var _parallax_pitch: float = 0.0
var _endless_nodes: Array[Node] = []
var _last_hovered_node: Node = null
var _pending_endless_did: String = ""
var _confirming_node: Node = null
var _endless_overview_pos: Vector3 = Vector3.ZERO
var _endless_overview_rot: Vector3 = Vector3.ZERO
var _active_zoom_tween: Tween = null
var _left_container_width: float = 450.0

@onready var camera_rig: Node3D = $MainMenuWorld/CameraRig
@onready var camera: Camera3D = $MainMenuWorld/CameraRig/Camera3D
@onready var camera_target_endless: Node3D = $CameraTargetEndless
@onready var left_ui_container: Control = $UILayer/LeftUIContainer
@onready var home_panel: Control = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/HomePanel
@onready var endless_button: Button = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/HomePanel/EndlessButton
@onready var quit_button: Button = $UILayer/LeftUIContainer/LeftPanel/CenterV/VBox/HomePanel/QuitButton
@onready var endless_nodes_parent: Node3D = $EndlessArea/EndlessNodes
@onready var level_select_back: Control = $UILayer/LevelSelectBack
@onready var back_to_menu_button: Button = $UILayer/LevelSelectBack/BackToMenuButton


func _ready() -> void:
	MusicManager.play_build_music(true)
	endless_button.pressed.connect(_on_endless_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	MobileSupport.enlarge_buttons($UILayer, 88.0)
	if MobileSupport.is_touch:
		var bottom: float = 20.0 + MobileSupport.safe_bottom
		level_select_back.offset_top = -(bottom + 88.0)
		level_select_back.offset_bottom = -bottom
	_hide_endless_nodes_for_home()
	await get_tree().process_frame
	_left_container_width = left_ui_container.size.x
	level_select_back.visible = false
	level_select_back.modulate = Color(1, 1, 1, 0)
	_set_level_select_back_interactive(false)


func _set_level_select_back_interactive(interactive: bool) -> void:
	var mf: Control.MouseFilter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	level_select_back.mouse_filter = mf
	back_to_menu_button.mouse_filter = mf


func _hide_endless_nodes_for_home() -> void:
	for child in endless_nodes_parent.get_children():
		if child.has_method("set_menu_fade_alpha"):
			child.call("set_menu_fade_alpha", 0.0)
		if child is Area3D:
			(child as Area3D).input_ray_pickable = false


func _process(delta: float) -> void:
	if _state == State.ENDLESS_SELECT:
		_update_camera_parallax(delta)
		_sync_endless_node_hover()


func _update_camera_parallax(delta: float) -> void:
	var target_yaw: float = 0.0
	var target_pitch: float = 0.0
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
	if _state != State.ENDLESS_SELECT:
		return
	if event is InputEventMouseMotion:
		_update_hover_at_screen_pos((event as InputEventMouseMotion).position)


func _sync_endless_node_hover() -> void:
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
	if collider is Area3D:
		var owner: Node = collider as Area3D
		while owner:
			if owner.has_method("setup") and owner.has_signal("selected"):
				return owner
			owner = owner.get_parent()
	return null


## Returns a Transform3D anchor: node pos + offset, looking at the node.
func _confirm_anchor_for_node(node: Node3D) -> Transform3D:
	var anchor_pos: Vector3 = node.global_position + ENDLESS_CONFIRM_ANCHOR_OFFSET
	var xf: Transform3D = Transform3D(Basis(), anchor_pos)
	xf = xf.looking_at(node.global_position, Vector3.UP)
	return xf


func _fade_left_out() -> void:
	left_ui_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween: Tween = left_ui_container.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(left_ui_container, "position:x", -_left_container_width, LEFT_FADE_DURATION)
	tween.parallel().tween_property(left_ui_container, "modulate", Color(1, 1, 1, 0), LEFT_FADE_DURATION)


func _fade_left_in() -> void:
	var tween: Tween = left_ui_container.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(left_ui_container, "position:x", 0.0, LEFT_FADE_DURATION)
	tween.parallel().tween_property(left_ui_container, "modulate", Color(1, 1, 1, 1), LEFT_FADE_DURATION)
	tween.tween_callback(func(): left_ui_container.mouse_filter = Control.MOUSE_FILTER_STOP)


func _on_endless_pressed() -> void:
	_state = State.ENDLESS_SELECT
	_play_sfx("play_ui_confirm")
	_fade_left_out()
	_pan_camera_to_endless_then_configure_and_fade()


func _pan_camera_to_endless_then_configure_and_fade() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_position", camera_target_endless.global_position, PAN_DURATION)
	tween.parallel().tween_property(camera_rig, "global_rotation", camera_target_endless.global_rotation, PAN_DURATION)
	tween.tween_callback(_after_pan_configure_endless_and_fade_in)


func _after_pan_configure_endless_and_fade_in() -> void:
	_configure_endless_nodes()
	_set_all_endless_nodes_menu_fade(0.0)
	_block_endless_nodes_picking()
	level_select_back.visible = true
	level_select_back.modulate = Color(1, 1, 1, 0)
	_set_level_select_back_interactive(false)
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(_set_all_endless_nodes_menu_fade, 0.0, 1.0, LEVEL_NODES_FADE_DURATION)
	tween.parallel().tween_property(level_select_back, "modulate", Color(1, 1, 1, 1), LEVEL_NODES_FADE_DURATION)
	tween.tween_callback(func():
		_endless_overview_pos = camera_rig.global_position
		_endless_overview_rot = camera_rig.global_rotation
		_restore_endless_nodes_picking()
		_set_level_select_back_interactive(true)
	)


func _configure_endless_nodes() -> void:
	_endless_nodes.clear()
	for child in endless_nodes_parent.get_children():
		if not child.has_method("setup"):
			continue
		child.setup({}, true, false)
		if child.has_method("set_holo_camera"):
			child.call("set_holo_camera", camera)
		if child.has_signal("selected"):
			if child.selected.is_connected(_on_endless_level_node_selected):
				child.selected.disconnect(_on_endless_level_node_selected)
			child.selected.connect(_on_endless_level_node_selected)
		_endless_nodes.append(child)


func _on_endless_level_node_selected(entry: Dictionary) -> void:
	if _state != State.ENDLESS_SELECT:
		return
	var did: String = String(entry.get("difficulty_id", ""))
	if did.is_empty():
		return
	var eid: String = String(entry.get("id", ""))
	if eid.is_empty():
		eid = "endless_" + did
	var node: Node = null
	for n in _endless_nodes:
		if n.has_method("setup") and String(n.entry.get("id", "")) == eid:
			node = n
			break
	if node == null:
		return
	_begin_endless_confirm(node, did)


func _begin_endless_confirm(node: Node, did: String) -> void:
	_state = State.ENDLESS_CONFIRM
	_pending_endless_did = did
	_confirming_node = node
	_endless_overview_pos = camera_rig.global_position
	_endless_overview_rot = camera_rig.global_rotation
	_block_endless_nodes_picking()
	if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
		_last_hovered_node.set_hovered(false)
	_last_hovered_node = null
	_parallax_yaw = 0.0
	_parallax_pitch = 0.0
	camera.rotation = Vector3.ZERO
	var mode_name: String = _endless_mode_display_name(did)
	var blurb: String = ""
	if node is LevelNode3D:
		blurb = (node as LevelNode3D).caption_blurb
	var mini: Node = null
	if node.has_method("get_mini_holo"):
		mini = node.call("get_mini_holo")
	if mini and mini.has_method("set_text"):
		mini.call("set_text", "You've selected %s" % mode_name, blurb)
	var anchor: Transform3D = _confirm_anchor_for_node(node as Node3D)
	if _active_zoom_tween:
		_active_zoom_tween.kill()
	_active_zoom_tween = create_tween()
	_active_zoom_tween.set_ease(Tween.EASE_IN_OUT)
	_active_zoom_tween.set_trans(Tween.TRANS_CUBIC)
	_active_zoom_tween.set_parallel(true)
	_active_zoom_tween.tween_property(camera_rig, "global_position", anchor.origin, ENDLESS_ZOOM_DURATION)
	_active_zoom_tween.tween_property(camera_rig, "global_rotation", anchor.basis.get_euler(), ENDLESS_ZOOM_DURATION)
	_active_zoom_tween.set_parallel(false)
	_active_zoom_tween.tween_callback(func():
		_active_zoom_tween = null
		_after_zoom_in_show_confirm(mini)
	)


func _after_zoom_in_show_confirm(mini: Node) -> void:
	if _state != State.ENDLESS_CONFIRM or mini == null or not is_instance_valid(mini):
		return
	if mini.has_method("set_confirm_mode"):
		mini.call("set_confirm_mode", true, true)
	if mini.has_signal("confirm_pressed"):
		mini.confirm_pressed.connect(_on_holo_confirm_pressed)
	if mini.has_signal("back_pressed"):
		mini.back_pressed.connect(_on_holo_back_pressed)
	_play_sfx("play_ui_confirm")


func _disconnect_holo_confirm_signals() -> void:
	if _confirming_node == null or not is_instance_valid(_confirming_node):
		return
	var mini: Node = _confirming_node.call("get_mini_holo") if _confirming_node.has_method("get_mini_holo") else null
	if mini == null or not is_instance_valid(mini):
		return
	if mini.has_signal("confirm_pressed") and mini.confirm_pressed.is_connected(_on_holo_confirm_pressed):
		mini.confirm_pressed.disconnect(_on_holo_confirm_pressed)
	if mini.has_signal("back_pressed") and mini.back_pressed.is_connected(_on_holo_back_pressed):
		mini.back_pressed.disconnect(_on_holo_back_pressed)


func _cleanup_endless_confirm_ui_only() -> void:
	if _active_zoom_tween:
		_active_zoom_tween.kill()
		_active_zoom_tween = null
	_disconnect_holo_confirm_signals()
	var node: Node = _confirming_node
	if node and is_instance_valid(node):
		var mini: Node = node.call("get_mini_holo") if node.has_method("get_mini_holo") else null
		if mini and mini.has_method("set_confirm_mode"):
			mini.call("set_confirm_mode", false, false)
		_restore_endless_title_on_node(node)
	_pending_endless_did = ""
	_confirming_node = null


func _restore_endless_title_on_node(node: Node) -> void:
	if node is LevelNode3D:
		var ln: LevelNode3D = node as LevelNode3D
		var mini: Node = ln.get_mini_holo()
		if mini and mini.has_method("set_text"):
			mini.call("set_text", ln.caption, ln.caption_blurb)


func _on_holo_back_pressed() -> void:
	_cancel_endless_confirm_zoom()


func _on_holo_confirm_pressed() -> void:
	var did: String = _pending_endless_did
	_disconnect_holo_confirm_signals()
	if _confirming_node and is_instance_valid(_confirming_node):
		var mini: Node = _confirming_node.call("get_mini_holo") if _confirming_node.has_method("get_mini_holo") else null
		if mini and mini.has_method("set_confirm_mode"):
			mini.call("set_confirm_mode", false, false)
	_confirming_node = null
	_pending_endless_did = ""
	_state = State.ENDLESS_SELECT
	if did.is_empty():
		return
	var session: Node = get_node_or_null("/root/GameSession")
	if session and session.has_method("start_endless"):
		session.call("start_endless", 0, did)
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")
	_play_sfx("play_ui_confirm")


func _cancel_endless_confirm_zoom() -> void:
	if _state != State.ENDLESS_CONFIRM:
		return
	if _active_zoom_tween:
		_active_zoom_tween.kill()
		_active_zoom_tween = null
	_disconnect_holo_confirm_signals()
	var node: Node = _confirming_node
	if node and is_instance_valid(node):
		var mini: Node = node.call("get_mini_holo") if node.has_method("get_mini_holo") else null
		if mini and mini.has_method("set_confirm_mode"):
			mini.call("set_confirm_mode", false, false)
		_restore_endless_title_on_node(node)
	_pending_endless_did = ""
	_confirming_node = null
	_state = State.ENDLESS_SELECT
	_active_zoom_tween = create_tween()
	_active_zoom_tween.set_ease(Tween.EASE_IN_OUT)
	_active_zoom_tween.set_trans(Tween.TRANS_CUBIC)
	_active_zoom_tween.set_parallel(true)
	_active_zoom_tween.tween_property(camera_rig, "global_position", _endless_overview_pos, ENDLESS_ZOOM_DURATION)
	_active_zoom_tween.tween_property(camera_rig, "global_rotation", _endless_overview_rot, ENDLESS_ZOOM_DURATION)
	_active_zoom_tween.set_parallel(false)
	_active_zoom_tween.tween_callback(func():
		_active_zoom_tween = null
		_restore_endless_nodes_picking()
		_play_sfx("play_ui_confirm")
	)


func _endless_mode_display_name(difficulty_id: String) -> String:
	match difficulty_id:
		"easy":
			return "Easy"
		"normal":
			return "Normal"
		"hard":
			return "Hard"
		"impossible":
			return "Impossible"
		_:
			return difficulty_id.capitalize()


func _set_all_endless_nodes_menu_fade(alpha: float) -> void:
	for node in _endless_nodes:
		if node.has_method("set_menu_fade_alpha"):
			node.call("set_menu_fade_alpha", alpha)


func _block_endless_nodes_picking() -> void:
	for node in _endless_nodes:
		if node is Area3D:
			(node as Area3D).input_ray_pickable = false


func _restore_endless_nodes_picking() -> void:
	for node in _endless_nodes:
		if node is Area3D:
			(node as Area3D).input_ray_pickable = true


func _on_back_to_menu_pressed() -> void:
	if _state == State.ENDLESS_CONFIRM:
		_cleanup_endless_confirm_ui_only()
	if _last_hovered_node and _last_hovered_node.has_method("set_hovered"):
		_last_hovered_node.set_hovered(false)
	_last_hovered_node = null
	_set_level_select_back_interactive(false)
	_restore_endless_nodes_picking()
	_state = State.HOME
	_set_all_endless_nodes_menu_fade(0.0)
	_block_endless_nodes_picking()
	_pan_camera_home()
	_fade_left_in()
	_play_sfx("play_ui_confirm")


func _pan_camera_home() -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(camera_rig, "global_position", CAMERA_HOME_POS, PAN_DURATION)
	tween.parallel().tween_property(camera_rig, "rotation", CAMERA_HOME_ROT, PAN_DURATION)
	tween.parallel().tween_property(level_select_back, "modulate", Color(1, 1, 1, 0), PAN_DURATION)
	tween.tween_callback(func(): level_select_back.visible = false)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _play_sfx(method_name: String) -> void:
	var sfx: Node = get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method(method_name):
		sfx.call(method_name)
