extends Camera3D
## RTS Camera - Handles edge panning and zoom for tilted 3D view

# Zoom limits (distance from look-at point; lower = zoomed in)
const MIN_ZOOM_DISTANCE: float = 15.0
const MAX_ZOOM_DISTANCE: float = 80.0

@export_group("Movement")
@export var pan_speed: float = 20.0
@export var edge_pan_margin: float = 8.0  # Pixels from screen edge (very close to edge)
@export var edge_pan_speed: float = 15.0
@export var enable_edge_panning: bool = true
@export var enable_keyboard_panning: bool = true
@export var enable_drag_panning: bool = true

@export_group("Zoom")
@export var min_zoom_distance: float = MIN_ZOOM_DISTANCE
@export var max_zoom_distance: float = MAX_ZOOM_DISTANCE
@export var zoom_speed: float = 5.0
@export var zoom_smoothing: float = 10.0

@export_group("Camera Angle")
@export var camera_pitch: float = 60.0  # Degrees from horizontal (60 = looking down at 60 degrees)

@export_group("Bounds")
@export var enable_bounds: bool = true
@export var bounds_min: Vector3 = Vector3(-500, 0, -500)
@export var bounds_max: Vector3 = Vector3(500, 100, 500)

# Target look-at point on ground
var _target_look_at: Vector3 = Vector3.ZERO
var _target_zoom: float = 50.0
var _is_dragging: bool = false
var _drag_start_mouse_pos: Vector2
var _drag_start_look_at: Vector3

# Debug sphere to show mouse position
var _debug_sphere: MeshInstance3D = null
@export var show_debug_sphere: bool = false


func _ready() -> void:
	if show_debug_sphere:
		_create_debug_sphere()
	# Initialize from current position - calculate look-at point
	var pitch_rad: float = deg_to_rad(camera_pitch)
	_target_zoom = global_position.y / sin(pitch_rad) if sin(pitch_rad) > 0.01 else 50.0
	_target_look_at = Vector3(global_position.x, 0, global_position.z + global_position.y / tan(pitch_rad))
	_update_camera_position_immediate()


func _process(delta: float) -> void:
	_handle_edge_panning(delta)
	_handle_keyboard_panning(delta)
	_handle_keyboard_zoom(delta)
	_smooth_movement(delta)
	_clamp_to_bounds()
	_update_debug_sphere()


func _unhandled_input(event: InputEvent) -> void:
	_handle_zoom(event)
	_handle_drag_panning(event)


func _handle_edge_panning(delta: float) -> void:
	if not enable_edge_panning:
		return
	
	if BuildManager.is_in_build_mode:
		return
	
	var viewport: Viewport = get_viewport()
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var screen_size: Vector2 = viewport.get_visible_rect().size
	
	var pan_direction: Vector3 = Vector3.ZERO
	
	# Check edges
	if mouse_pos.x < edge_pan_margin:
		pan_direction.x -= 1
	elif mouse_pos.x > screen_size.x - edge_pan_margin:
		pan_direction.x += 1
	
	if mouse_pos.y < edge_pan_margin:
		pan_direction.z -= 1
	elif mouse_pos.y > screen_size.y - edge_pan_margin:
		pan_direction.z += 1
	
	if pan_direction != Vector3.ZERO:
		pan_direction = pan_direction.normalized()
		_target_look_at += pan_direction * edge_pan_speed * delta * (_target_zoom / 30.0)


func _handle_keyboard_panning(delta: float) -> void:
	if not enable_keyboard_panning:
		return
	
	var pan_direction: Vector3 = Vector3.ZERO
	
	if Input.is_action_pressed("camera_pan_up"):
		pan_direction.z -= 1
	if Input.is_action_pressed("camera_pan_down"):
		pan_direction.z += 1
	if Input.is_action_pressed("camera_pan_left"):
		pan_direction.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		pan_direction.x += 1
	
	if pan_direction != Vector3.ZERO:
		pan_direction = pan_direction.normalized()
		_target_look_at += pan_direction * pan_speed * delta * (_target_zoom / 30.0)


func _handle_keyboard_zoom(delta: float) -> void:
	if BuildManager.is_in_build_mode:
		return
	var zoom_direction: float = 0.0
	if Input.is_action_pressed("camera_zoom_in"):
		zoom_direction = -1.0
	elif Input.is_action_pressed("camera_zoom_out"):
		zoom_direction = 1.0
	if zoom_direction != 0.0:
		var viewport: Viewport = get_viewport()
		var center: Vector2 = viewport.get_visible_rect().size / 2.0
		var old_zoom: float = _target_zoom
		var zoom_step: float = zoom_direction * zoom_speed * delta * 8.0
		_target_zoom = clampf(
			_target_zoom + zoom_step,
			min_zoom_distance,
			max_zoom_distance
		)
		if _target_zoom != old_zoom:
			var world_pos: Vector3 = _get_world_position_at_mouse(center)
			if world_pos:
				var zoom_factor: float = _target_zoom / old_zoom
				var offset: Vector3 = _target_look_at - Vector3(world_pos.x, 0, world_pos.z)
				_target_look_at = Vector3(world_pos.x, 0, world_pos.z) + offset * zoom_factor


func _handle_drag_panning(event: InputEvent) -> void:
	if not enable_drag_panning:
		return
	
	if BuildManager.is_in_build_mode:
		return
	
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_event.pressed:
				_is_dragging = true
				_drag_start_mouse_pos = mouse_event.position
				_drag_start_look_at = _target_look_at
			else:
				_is_dragging = false
	
	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var delta_pos: Vector2 = motion_event.position - _drag_start_mouse_pos
		var drag_scale: float = _target_zoom / 500.0  # Scale movement based on zoom
		_target_look_at = _drag_start_look_at - Vector3(delta_pos.x * drag_scale, 0, delta_pos.y * drag_scale)


func _handle_zoom(event: InputEvent) -> void:
	if BuildManager.is_in_build_mode:
		return
	
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		
		if mouse_event.pressed:
			var zoom_direction: float = 0.0
			
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_direction = -1.0
			elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_direction = 1.0
			
			if zoom_direction != 0.0:
				# Zoom toward/away from mouse position
				var old_zoom: float = _target_zoom
				_target_zoom = clampf(
					_target_zoom + zoom_direction * zoom_speed,
					min_zoom_distance,
					max_zoom_distance
				)
				
				# Adjust look-at position to zoom toward mouse cursor
				if _target_zoom != old_zoom:
					var mouse_pos: Vector2 = mouse_event.position
					var world_pos: Vector3 = _get_world_position_at_mouse(mouse_pos)
					if world_pos:
						var zoom_factor: float = _target_zoom / old_zoom
						var offset: Vector3 = _target_look_at - Vector3(world_pos.x, 0, world_pos.z)
						_target_look_at = Vector3(world_pos.x, 0, world_pos.z) + offset * zoom_factor


func _smooth_movement(delta: float) -> void:
	# Calculate camera position based on look-at point and zoom distance
	var pitch_rad: float = deg_to_rad(camera_pitch)
	var horizontal_offset: float = _target_zoom * cos(pitch_rad)
	var vertical_offset: float = _target_zoom * sin(pitch_rad)

	var target_pos: Vector3 = Vector3(
		_target_look_at.x,
		vertical_offset,
		_target_look_at.z + horizontal_offset
	)
	
	# Smoothly interpolate position
	global_position = global_position.lerp(target_pos, zoom_smoothing * delta)
	
	# Set fixed rotation instead of look_at to prevent jarring rotation changes
	rotation.x = -pitch_rad
	rotation.y = 0
	rotation.z = 0


func _clamp_to_bounds() -> void:
	if not enable_bounds:
		return
	
	_target_look_at.x = clampf(_target_look_at.x, bounds_min.x, bounds_max.x)
	_target_look_at.z = clampf(_target_look_at.z, bounds_min.z, bounds_max.z)
	_target_zoom = clampf(_target_zoom, min_zoom_distance, max_zoom_distance)


func _get_world_position_at_mouse(mouse_pos: Vector2) -> Vector3:
	var from: Vector3 = project_ray_origin(mouse_pos)
	var to: Vector3 = from + project_ray_normal(mouse_pos) * 1000
	
	# Intersect with Y=0 plane
	var plane: Plane = Plane(Vector3.UP, 0)
	var intersection: Variant = plane.intersects_ray(from, to - from)
	
	return intersection if intersection else Vector3.ZERO


## Get current zoom distance (for star plane scaling etc.)
func get_zoom_level() -> float:
	return _target_zoom


## Get the world position under the mouse cursor
func get_mouse_world_position() -> Vector3:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	return _get_world_position_at_mouse(mouse_pos)


## Instantly move camera to look at position
func set_camera_position(pos: Vector3) -> void:
	_target_look_at = Vector3(pos.x, 0, pos.z)
	_update_camera_position_immediate()


## Instantly set zoom level
func set_zoom(zoom: float) -> void:
	_target_zoom = clampf(zoom, min_zoom_distance, max_zoom_distance)
	_update_camera_position_immediate()


func _update_camera_position_immediate() -> void:
	var pitch_rad: float = deg_to_rad(camera_pitch)
	var horizontal_offset: float = _target_zoom * cos(pitch_rad)
	var vertical_offset: float = _target_zoom * sin(pitch_rad)

	global_position = Vector3(
		_target_look_at.x,
		vertical_offset,
		_target_look_at.z + horizontal_offset
	)
	
	# Set fixed rotation instead of look_at
	rotation.x = -pitch_rad
	rotation.y = 0
	rotation.z = 0


func _create_debug_sphere() -> void:
	_debug_sphere = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_debug_sphere.mesh = sphere
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 1.0, 0.8)  # Magenta
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 1.0)
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_sphere.material_override = material
	
	# Add to scene root so it's not affected by camera movement
	_debug_sphere.visible = show_debug_sphere
	get_tree().root.call_deferred("add_child", _debug_sphere)


func _update_debug_sphere() -> void:
	if not _debug_sphere or not show_debug_sphere:
		return
	
	var world_pos: Vector3 = get_mouse_world_position()
	_debug_sphere.global_position = Vector3(world_pos.x, 0.5, world_pos.z)
	_debug_sphere.visible = true
