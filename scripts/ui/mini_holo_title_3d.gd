extends Node3D
class_name MiniHoloTitle3D
## Compact holo panel above a level node (same SubViewport + holo shader style as [HoloBillboard3D]).
## Uses the menu camera's basis (screen-parallel), not per-point look-at, so labels stay level and readable.
## Confirm / Back buttons + Area3D forward clicks to the SubViewport when [method set_confirm_mode] is active.

const PIXEL_SIZE: float = 0.0022
const CONFIRM_FADE_DURATION: float = 0.35

signal confirm_pressed
signal back_pressed

@onready var sub_viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Sprite3D
@onready var area: Area3D = $Area3D
@onready var title_label: Label = $SubViewport/HoloPanel/VBox/TitleLabel
@onready var blurb_label: Label = $SubViewport/HoloPanel/VBox/BlurbLabel
@onready var button_row: HBoxContainer = $SubViewport/HoloPanel/VBox/ButtonRow
@onready var back_button: Button = $SubViewport/HoloPanel/VBox/ButtonRow/BackButton
@onready var confirm_button: Button = $SubViewport/HoloPanel/VBox/ButtonRow/ConfirmButton

var _camera: Camera3D = null
var _confirm_tween: Tween = null


func _ready() -> void:
	sprite.texture = sub_viewport.get_texture()
	sprite.pixel_size = PIXEL_SIZE
	area.input_event.connect(_on_area_input_event)
	back_button.pressed.connect(func(): back_pressed.emit())
	confirm_button.pressed.connect(func(): confirm_pressed.emit())
	button_row.modulate = Color(1, 1, 1, 0)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func set_text(title: String, blurb: String) -> void:
	title_label.text = title
	blurb_label.text = blurb
	blurb_label.visible = not blurb.is_empty()


func set_menu_fade_alpha(a: float) -> void:
	var c: float = clampf(a, 0.0, 1.0)
	sprite.modulate = Color(1, 1, 1, c)


func set_confirm_mode(active: bool, fade_in_buttons: bool = true) -> void:
	if active:
		button_row.visible = true
		if fade_in_buttons:
			if _confirm_tween:
				_confirm_tween.kill()
			_confirm_tween = create_tween()
			_confirm_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			button_row.modulate = Color(1, 1, 1, 0)
			_confirm_tween.tween_property(button_row, "modulate", Color(1, 1, 1, 1), CONFIRM_FADE_DURATION)
		else:
			button_row.modulate = Color(1, 1, 1, 1)
		area.collision_layer = 1
	else:
		if _confirm_tween:
			_confirm_tween.kill()
			_confirm_tween = null
		button_row.visible = false
		button_row.modulate = Color(1, 1, 1, 0)
		area.collision_layer = 0


func _process(_delta: float) -> void:
	if not _camera:
		return
	var b: Basis = _camera.global_transform.basis.orthonormalized()
	global_transform = Transform3D(b, global_position)


func _on_area_input_event(_cam: Node, event: InputEvent, hit_pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if area.collision_layer == 0:
		return
	var local_pos: Vector3 = sprite.to_local(hit_pos)
	var vp_size: Vector2 = Vector2(sub_viewport.size)
	var x: float = local_pos.x / PIXEL_SIZE + vp_size.x * 0.5
	var y: float = -local_pos.y / PIXEL_SIZE + vp_size.y * 0.5
	var vp_pos: Vector2 = Vector2(x, y)

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event.duplicate() as InputEventMouseButton
		mb.position = vp_pos
		mb.global_position = vp_pos
		sub_viewport.push_input(mb)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event.duplicate() as InputEventMouseMotion
		mm.position = vp_pos
		mm.global_position = vp_pos
		sub_viewport.push_input(mm)
