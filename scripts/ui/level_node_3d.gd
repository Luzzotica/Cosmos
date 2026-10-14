extends Area3D
class_name LevelNode3D
## 3D level node for the star-map style selection. Dotted green hologram circle.
## Set map_id in the inspector to link this node to a story map.

@export var map_id: String = ""
## When set, this node selects endless difficulty instead of a story map ([member map_id] ignored).
@export var endless_difficulty_id: String = ""
## Optional holo title above the circle (e.g. Easy / Normal).
@export var caption: String = ""
## Optional short line under the title (same holo panel).
@export var caption_blurb: String = ""

const MINI_HOLO_TITLE_SCENE: PackedScene = preload("res://scenes/ui/mini_holo_title_3d.tscn")

var _mini_holo: Node = null

signal selected(entry: Dictionary)

const ROTATE_SPEED_NORMAL: float = 0.14
const ROTATE_SPEED_FOCUSED: float = 0.72

var entry: Dictionary = {}:
	set(value):
		entry = value

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _rotation_focused: bool = false


func _ready() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D")
	if _mesh_instance:
		var base_mat: Material = _mesh_instance.get_surface_override_material(0)
		if base_mat == null and _mesh_instance.mesh:
			base_mat = _mesh_instance.mesh.surface_get_material(0)
		if base_mat:
			_material = base_mat.duplicate() as ShaderMaterial
			_mesh_instance.set_surface_override_material(0, _material)
	input_event.connect(_on_input_event)
	if not endless_difficulty_id.is_empty():
		entry = { "difficulty_id": endless_difficulty_id, "id": "endless_" + endless_difficulty_id }
	elif entry.is_empty() and not map_id.is_empty():
		_resolve_entry_from_manifest()
	_add_caption_if_needed()


func _process(delta: float) -> void:
	if _mesh_instance:
		var speed: float = ROTATE_SPEED_FOCUSED if _rotation_focused else ROTATE_SPEED_NORMAL
		_mesh_instance.rotate_object_local(Vector3.UP, delta * speed)


func set_rotation_focused(focused: bool) -> void:
	_rotation_focused = focused


func _resolve_entry_from_manifest() -> void:
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager == null:
		return
	var manifest: Dictionary = story_manager.manifest
	var maps: Array = manifest.get("maps", [])
	for e in maps:
		if e is Dictionary and String(e.get("id", "")) == map_id:
			entry = e
			return


func setup(p_entry: Dictionary, unlocked: bool, beaten: bool) -> void:
	if not p_entry.is_empty():
		entry = p_entry
	elif not endless_difficulty_id.is_empty():
		entry = { "difficulty_id": endless_difficulty_id, "id": "endless_" + endless_difficulty_id }
	set_locked(not unlocked)
	set_completed(beaten)


func _add_caption_if_needed() -> void:
	if caption.is_empty():
		return
	var mini: Node = MINI_HOLO_TITLE_SCENE.instantiate()
	mini.position = Vector3(0, 0.58, 0)
	add_child(mini)
	_mini_holo = mini
	if mini.has_method("set_text"):
		mini.call("set_text", caption, caption_blurb)


func get_mini_holo() -> Node:
	return _mini_holo


func set_holo_camera(cam: Camera3D) -> void:
	if _mini_holo and _mini_holo.has_method("set_camera"):
		_mini_holo.call("set_camera", cam)


func set_locked(locked: bool) -> void:
	if _material:
		_material.set_shader_parameter("is_locked", 1.0 if locked else 0.0)
	input_ray_pickable = not locked


func set_completed(completed: bool) -> void:
	if _material and completed:
		_material.set_shader_parameter("color", Color(0.3, 0.8, 0.35, 0.8))


func set_menu_fade_alpha(a: float) -> void:
	if _material:
		_material.set_shader_parameter("display_alpha", clampf(a, 0.0, 1.0))
	if _mini_holo and _mini_holo.has_method("set_menu_fade_alpha"):
		_mini_holo.call("set_menu_fade_alpha", a)


func set_hovered(hovered: bool) -> void:
	if _material:
		_material.set_shader_parameter("glow_strength", 3.0 if hovered else 1.8)
	if _mesh_instance:
		var s: float = 1.05 if hovered else 1.0
		_mesh_instance.scale = Vector3(s, s, s)


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			selected.emit(entry)
