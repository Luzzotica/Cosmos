extends Area3D
class_name LevelNode3D
## 3D level node for the star-map style selection. Dotted green hologram circle.
## Set map_id in the inspector to link this node to a story map.

@export var map_id: String = ""

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
	# Resolve entry from map_id if not set
	if entry.is_empty() and not map_id.is_empty():
		_resolve_entry_from_manifest()


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
	entry = p_entry
	set_locked(not unlocked)
	set_completed(beaten)


func set_locked(locked: bool) -> void:
	if _material:
		_material.set_shader_parameter("is_locked", 1.0 if locked else 0.0)
	input_ray_pickable = not locked


func set_completed(completed: bool) -> void:
	if _material and completed:
		_material.set_shader_parameter("color", Color(0.3, 0.8, 0.35, 0.8))


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
