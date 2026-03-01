extends Node3D
class_name SelectionVisuals
## Shared visual feedback for hover and selection.

@export var selection_color_player: Color = Color(0.2, 1.0, 0.3, 0.8)
@export var selection_color_enemy: Color = Color(1.0, 0.2, 0.2, 0.8)
@export var selection_color_neutral: Color = Color(1.0, 0.9, 0.2, 0.8)
@export var hover_color: Color = Color(1.0, 0.95, 0.35, 0.6)
@export var selection_ring_height: float = 0.1
@export var hover_ring_height: float = 0.1
@export var selection_thickness: float = 0.15
@export var hover_thickness: float = 0.12
@export var radius_padding: float = 0.35

var _selectable: Node = null
var _selection_ring: MeshInstance3D = null
var _hover_ring: MeshInstance3D = null
var _current_radius: float = 1.2


func _ready() -> void:
	_selectable = get_parent().get_node_or_null("SelectableComponent")
	if _selectable == null:
		return

	_current_radius = _compute_radius()
	_selection_ring = _create_ring(_current_radius, selection_thickness, selection_ring_height)
	_hover_ring = _create_ring(_current_radius + 0.2, hover_thickness, hover_ring_height)

	_selection_ring.visible = false
	_hover_ring.visible = false

	_update_ring_color()

	_selectable.selected_changed.connect(_on_selected_changed)
	_selectable.hover_changed.connect(_on_hover_changed)
	_selectable.details_changed.connect(_update_ring_color)


func _compute_radius() -> float:
	var area: Area3D = get_parent().get_node_or_null("SelectableComponent") as Area3D
	if area == null:
		area = get_parent().get_node_or_null("Area3D") as Area3D
	if area:
		var shape_node: CollisionShape3D = area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape:
			if shape_node.shape is SphereShape3D:
				return (shape_node.shape as SphereShape3D).radius + radius_padding
			if shape_node.shape is CapsuleShape3D:
				return (shape_node.shape as CapsuleShape3D).radius + radius_padding
	return 1.2


func _create_ring(radius: float, thickness: float, ring_height: float) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.05)
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 32
	ring.mesh = mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	ring.material_override = mat

	ring.position.y = ring_height
	add_child(ring)
	return ring


func _on_selected_changed(is_selected: bool) -> void:
	if _selection_ring:
		_selection_ring.visible = is_selected
	if is_selected and _hover_ring:
		_hover_ring.visible = false
	elif _hover_ring:
		_hover_ring.visible = _selectable.is_hovered()


func _on_hover_changed(is_hovered: bool) -> void:
	if _hover_ring:
		_hover_ring.visible = is_hovered and not _selectable.is_selected()


func _update_ring_color() -> void:
	if _selection_ring == null:
		return

	var faction: String = _selectable.get_faction()
	var sel_color: Color = selection_color_neutral
	match faction:
		"player":
			sel_color = selection_color_player
		"enemy":
			sel_color = selection_color_enemy
		_:
			sel_color = selection_color_neutral

	var sel_mat: StandardMaterial3D = _selection_ring.material_override as StandardMaterial3D
	if sel_mat:
		sel_mat.albedo_color = sel_color
		sel_mat.emission = Color(sel_color.r * 0.8, sel_color.g * 0.8, sel_color.b * 0.8, 1.0)
		sel_mat.emission_energy_multiplier = 2.5

	var hover_mat: StandardMaterial3D = _hover_ring.material_override as StandardMaterial3D
	if hover_mat:
		hover_mat.albedo_color = hover_color
		hover_mat.emission = Color(hover_color.r * 0.8, hover_color.g * 0.8, hover_color.b * 0.8, 1.0)
		hover_mat.emission_energy_multiplier = 2.0
