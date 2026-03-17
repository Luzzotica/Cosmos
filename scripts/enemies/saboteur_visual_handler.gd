extends ShipVisualHandler
class_name SaboteurVisualHandler
## Saboteur visuals: cone↔disc morph, shader params, barrier driven by C_SaboteurState.
## init() gets C_SaboteurState from entity and connects state_changed.

const CONE_TOP_RADIUS: float = 0.0
const CONE_BOTTOM_RADIUS: float = 0.35
const CONE_HEIGHT: float = 1.0
const DISC_RADIUS: float = 0.6
const DISC_HEIGHT: float = 0.08
## Rotation (radians) around X to tilt cone→disc so the disc lies flat (horizontal) instead of edge-on.
const DISC_TILT_RAD: float = TAU / 4.0


func init(entity: Node) -> void:
	var c_saboteur: C_SaboteurState = entity.get_component(C_SaboteurState) as C_SaboteurState
	if c_saboteur and not c_saboteur.state_changed.is_connected(_on_state_changed):
		c_saboteur.state_changed.connect(_on_state_changed)
	_ensure_morph_mesh_owned()
	if c_saboteur:
		apply_state(c_saboteur.state, c_saboteur.state_progress)


func _on_state_changed(new_state: int, progress: float) -> void:
	apply_state(new_state, progress)


func _ensure_morph_mesh_owned() -> void:
	var body_root: Node3D = get_parent() as Node3D
	if body_root == null:
		return
	var body_node: Node3D = body_root.get_node_or_null("Body")
	if body_node == null:
		return
	var morph: MeshInstance3D = body_node.get_node_or_null("MorphMesh") as MeshInstance3D
	if morph == null or morph.mesh == null:
		return
	if not morph.mesh is CylinderMesh:
		return
	# Duplicate mesh so each saboteur has its own - mutating shared resources affects all instances
	morph.mesh = morph.mesh.duplicate()


func _apply_shape_morph(mesh_instance: MeshInstance3D, new_state: int, progress: float) -> void:
	var mesh: CylinderMesh = mesh_instance.mesh as CylinderMesh
	if mesh == null:
		return
	var t: float
	match new_state:
		1:  # POWERING_UP - cone → disc
			t = ease(progress, 2.0)
		2:  # BLOCKING - disc
			t = 1.0
		3:  # POWERING_DOWN - disc → cone
			t = 1.0 - ease(progress, 0.5)
		_:  # MOVE_TO - cone
			t = 0.0
	mesh.top_radius = lerpf(CONE_TOP_RADIUS, DISC_RADIUS, t)
	mesh.bottom_radius = lerpf(CONE_BOTTOM_RADIUS, DISC_RADIUS, t)
	mesh.height = lerpf(CONE_HEIGHT, DISC_HEIGHT, t)
	# Rotate so disc lies flat (horizontal) instead of edge-on; lerp with shape
	mesh_instance.rotation.x = lerpf(0.0, DISC_TILT_RAD, t)


func apply_state(new_state: int, progress: float) -> void:
	var body_root: Node3D = get_parent() as Node3D
	if body_root == null:
		return
	var body_node: Node3D = body_root.get_node_or_null("Body")
	if body_node == null:
		return
	var barrier: Node3D = body_root.get_node_or_null("Barrier")
	for child in body_node.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child as MeshInstance3D
		_apply_shape_morph(mi, new_state, progress)
		var mat: Material = mi.get_active_material(0)
		if mat == null or not mat is ShaderMaterial:
			continue
		var sm: ShaderMaterial = mat as ShaderMaterial
		match new_state:
			1:  # POWERING_UP - charge: ramp emission with eased curve, crackle intensifies
				var eased: float = ease(progress, 2.0)
				sm.set_shader_parameter("emission_energy", 1.5 + eased * 2.5)
				sm.set_shader_parameter("crackle_speed", 3.0 + eased * 5.0)
				sm.set_shader_parameter("pulse_amount", 0.1 + eased * 0.25)
				sm.set_shader_parameter("crackle_density", 28.0 + eased * 12.0)
			2:  # BLOCKING - sustained glow, barrier visible
				sm.set_shader_parameter("emission_energy", 3.5)
				sm.set_shader_parameter("crackle_speed", 6.0)
				sm.set_shader_parameter("pulse_amount", 0.3)
				sm.set_shader_parameter("crackle_density", 36.0)
			3:  # POWERING_DOWN - exponential decay with flicker
				var decay: float = ease(1.0 - progress, 0.5)
				var flicker: float = sin(progress * 20.0) * 0.15 * decay
				sm.set_shader_parameter("emission_energy", 3.5 * decay + flicker)
				sm.set_shader_parameter("crackle_speed", 6.0 * decay + 2.0)
				sm.set_shader_parameter("pulse_amount", 0.3 * decay)
				sm.set_shader_parameter("crackle_density", 28.0 + 8.0 * decay)
			_:  # MOVE_TO - return to base emission
				sm.set_shader_parameter("emission_energy", 2.2)
				sm.set_shader_parameter("crackle_speed", 3.0)
				sm.set_shader_parameter("pulse_amount", 0.2)
				sm.set_shader_parameter("crackle_density", 28.0)
	if barrier:
		barrier.visible = (new_state == 2)
