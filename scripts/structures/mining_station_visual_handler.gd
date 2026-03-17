extends "res://scripts/structures/structure_visual_handler.gd"
class_name MiningStationVisualHandler
## Mining station visuals: beam to asteroid, pulse on mine, power-driven collector glow.

const C_MiningStationClass = preload("res://scripts/ecs/components/c_mining_station.gd")

var _mining_beam: MeshInstance3D = null
var _active_collector: MeshInstance3D = null
var _collector_rest_emission: float = 2.1
var _beam_visible_timer: float = 0.0
const BEAM_BRIGHT_DURATION: float = 0.5  ## Stay full brightness
const BEAM_FADE_DURATION: float = 0.35   ## Fade out time


@export var laser_origin: Node3D  ## Beam origin; falls back to body + Vector3(0, 1.5, 0) if unset


func _get_register_structure_props() -> Dictionary:
	return {"accent_no_shadow_mesh_names": ["ActiveCollector"]}


func init(entity: Node) -> void:
	super.init(entity)
	var body: Node3D = get_parent() as Node3D
	if body:
		_active_collector = body.get_node_or_null("VisualRoot/ActiveCollector") as MeshInstance3D
		if _active_collector:
			_active_collector.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat: StandardMaterial3D = _active_collector.get_active_material(0) as StandardMaterial3D
			if mat:
				_collector_rest_emission = mat.emission_energy_multiplier
	_create_mining_beam()


func fire_mining_beam() -> void:
	_beam_visible_timer = BEAM_BRIGHT_DURATION + BEAM_FADE_DURATION
	var body: Node3D = get_parent() as Node3D
	if body:
		var render_manager: Node = get_tree().root.get_node_or_null("StructureRenderManager")
		if render_manager and render_manager.has_method("pulse_structure"):
			render_manager.call("pulse_structure", body, 0.18)
	# Pulse the collector light when firing
	if _active_collector:
		var mat: StandardMaterial3D = _active_collector.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.5
			var timer: SceneTreeTimer = get_tree().create_timer(0.12)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(_active_collector):
					var reset_mat: StandardMaterial3D = _active_collector.get_active_material(0) as StandardMaterial3D
					if reset_mat:
						reset_mat.emission_energy_multiplier = _collector_rest_emission
			)
	if _mining_beam:
		_mining_beam.visible = true
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0
			mat.albedo_color.a = 1.0
	var sfx_manager: Node = get_tree().root.get_node_or_null("SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", "mining_pulse", -8.0)


func _create_mining_beam() -> void:
	_mining_beam = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.08
	cylinder.height = 1.0
	_mining_beam.mesh = cylinder
	var material: StandardMaterial3D = StandardMaterial3D.new()
	# Match ActiveCollector colors: albedo Color(0.95, 0.85, 0.2), emission Color(0.9, 0.75, 0.15)
	material.albedo_color = Color(0.95, 0.85, 0.2, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.75, 0.15, 1.0)
	material.emission_energy_multiplier = 5.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = 1  ## Draw in front of structure base
	_mining_beam.material_override = material
	_mining_beam.visible = false
	_mining_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mining_beam)


func _process(delta: float) -> void:
	super._process(delta)
	_update_mining_beam(delta)


func _update_mining_beam(delta: float) -> void:
	if not _mining_beam:
		return
	if _beam_visible_timer > 0:
		_beam_visible_timer -= delta
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			if _beam_visible_timer > BEAM_FADE_DURATION:
				# Bright phase: full emission and alpha
				mat.emission_energy_multiplier = 5.0
				mat.albedo_color.a = 1.0
			else:
				# Fade phase: fade from full to zero over BEAM_FADE_DURATION
				var fade_progress: float = _beam_visible_timer / BEAM_FADE_DURATION
				mat.emission_energy_multiplier = 5.0 * fade_progress
				mat.albedo_color.a = fade_progress
		if _beam_visible_timer <= 0:
			_mining_beam.visible = false
			return
	else:
		_mining_beam.visible = false
		return

	var c_mining = _get_component(C_MiningStationClass)
	if c_mining == null or c_mining.target_entity == null or not is_instance_valid(c_mining.target_entity):
		_mining_beam.visible = false
		return

	var body: Node3D = get_parent() as Node3D
	if body == null:
		return
	var start_pos: Vector3 = laser_origin.global_position if is_instance_valid(laser_origin) else body.global_position + Vector3(0, 1.5, 0)
	var end_pos: Vector3 = c_mining.target_entity.global_position
	var direction: Vector3 = end_pos - start_pos
	var distance: float = direction.length()
	if distance < 0.1:
		_mining_beam.visible = false
		return

	var midpoint: Vector3 = (start_pos + end_pos) / 2.0
	_mining_beam.global_position = midpoint
	var cylinder_mesh: CylinderMesh = _mining_beam.mesh as CylinderMesh
	if cylinder_mesh:
		cylinder_mesh.height = distance

	_mining_beam.rotation = Vector3.ZERO
	direction = direction.normalized()
	var up: Vector3 = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_mining_beam.look_at_from_position(midpoint, midpoint + direction, up)
	_mining_beam.rotate_object_local(Vector3(1, 0, 0), PI / 2)
