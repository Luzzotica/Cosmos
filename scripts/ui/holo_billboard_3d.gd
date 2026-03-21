extends Node3D
class_name HoloBillboard3D
## 3D hologram panel that floats above a level node.
## Renders UI in a SubViewport, displayed on a Sprite3D.
## Forwards mouse input to the SubViewport so buttons are interactive.

signal back_pressed
signal launch_pressed

const PHASE_DURATION: float = 0.16
const CONTENT_DURATION: float = 0.22
const PIXEL_SIZE: float = 0.003

## Point scale - tiny dot of green light
const POINT_SCALE: float = 0.015

var _holo_material: ShaderMaterial = null
var _camera: Camera3D = null

@onready var sub_viewport: SubViewport = $SubViewport
@onready var sprite: Sprite3D = $Sprite3D
@onready var area: Area3D = $Area3D
@onready var content_vbox: VBoxContainer = $SubViewport/HoloPanel/VBox
@onready var level_title: Label = $SubViewport/HoloPanel/VBox/LevelTitle
@onready var level_description: Label = $SubViewport/HoloPanel/VBox/LevelDescription
@onready var launch_button: Button = $SubViewport/HoloPanel/VBox/ButtonRow/LaunchButton
@onready var back_button_node: Button = $SubViewport/HoloPanel/VBox/ButtonRow/BackButton
@onready var holo_bg: ColorRect = $SubViewport/HoloPanel/HoloBG


func _ready() -> void:
	sprite.texture = sub_viewport.get_texture()
	area.input_event.connect(_on_area_input_event)
	back_button_node.pressed.connect(func(): back_pressed.emit())
	launch_button.pressed.connect(func(): launch_pressed.emit())
	_holo_material = holo_bg.material as ShaderMaterial
	visible = false


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _process(_delta: float) -> void:
	if visible and _camera:
		_face_camera()


func _face_camera() -> void:
	var cam_pos: Vector3 = _camera.global_position
	var my_pos: Vector3 = global_position
	var forward: Vector3 = (cam_pos - my_pos).normalized()
	# Billboard +Z (front face) toward camera, world UP keeps it upright
	global_transform.basis = Basis.looking_at(-forward, Vector3.UP)


func set_content(title_text: String, desc_text: String, can_launch: bool) -> void:
	level_title.text = title_text
	level_description.text = desc_text
	launch_button.disabled = not can_launch


func show_billboard() -> void:
	visible = true
	scale = Vector3(POINT_SCALE, POINT_SCALE, 1.0)
	content_vbox.modulate = Color(1, 1, 1, 0)
	content_vbox.scale = Vector2(0.6, 0.6)
	var vbox_size: Vector2 = content_vbox.size
	if vbox_size.x > 0 and vbox_size.y > 0:
		content_vbox.pivot_offset = vbox_size / 2.0
	else:
		content_vbox.pivot_offset = Vector2(180, 109)
	if _holo_material:
		_holo_material.set_shader_parameter("open_progress", 0.0)

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 1: point -> horizontal green line (expand x)
	tween.tween_property(self, "scale", Vector3(1.0, POINT_SCALE, 1.0), PHASE_DURATION)
	if _holo_material:
		tween.parallel().tween_property(
			_holo_material, "shader_parameter/open_progress", 0.35, PHASE_DURATION
		)
	# Phase 2: line -> open up (expand y)
	tween.tween_property(self, "scale", Vector3.ONE, PHASE_DURATION)
	if _holo_material:
		tween.parallel().tween_property(
			_holo_material, "shader_parameter/open_progress", 1.0, PHASE_DURATION
		)
	# Phase 3: UI content fades and scales in from background to foreground
	tween.tween_property(content_vbox, "modulate", Color(1, 1, 1, 1), CONTENT_DURATION)
	tween.parallel().tween_property(content_vbox, "scale", Vector2.ONE, CONTENT_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_billboard(on_done: Callable = Callable()) -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# Phase 1: UI content fades and scales back into background
	tween.tween_property(content_vbox, "modulate", Color(1, 1, 1, 0), CONTENT_DURATION * 0.7)
	tween.parallel().tween_property(content_vbox, "scale", Vector2(0.6, 0.6), CONTENT_DURATION * 0.7)
	# Phase 2: close down (scale.y 1 -> line)
	tween.tween_property(self, "scale", Vector3(1.0, POINT_SCALE, 1.0), PHASE_DURATION)
	if _holo_material:
		tween.parallel().tween_property(
			_holo_material, "shader_parameter/open_progress", 0.35, PHASE_DURATION
		)
	# Phase 3: collapse to point (scale.x 1 -> 0)
	tween.tween_property(self, "scale", Vector3(POINT_SCALE, POINT_SCALE, 1.0), PHASE_DURATION)
	if _holo_material:
		tween.parallel().tween_property(
			_holo_material, "shader_parameter/open_progress", 0.0, PHASE_DURATION
		)
	tween.tween_callback(func():
		visible = false
		if on_done.is_valid():
			on_done.call()
	)


func _on_area_input_event(_cam: Node, event: InputEvent, hit_pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
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
