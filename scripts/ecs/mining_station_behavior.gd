extends "res://scripts/ecs/structure_behavior.gd"
class_name MiningStationBehavior
## Structure behavior for Mining Station - mining beam visual and powered state.

var _mining_beam: MeshInstance3D = null
var _beam_visible_timer: float = 0.0
const BEAM_VISIBLE_DURATION: float = 0.5
const BEAM_FADE_SPEED: float = 4.0


func _ready() -> void:
	super._ready()
	_create_mining_beam()
	var entity: Node = _get_entity()
	if entity and entity.has_signal("minerals_extracted"):
		entity.minerals_extracted.connect(_on_minerals_extracted)


func _process(delta: float) -> void:
	update_mining_beam(delta)


func apply_post_register() -> void:
	var entity: Node = _get_entity()
	if not entity or not entity.has_method("get_component"):
		return
	var data: Resource = BuildManager.get_building_data(entity.building_type) if BuildManager else null
	if data == null:
		return
	var configured_range: Variant = data.get("action_range")
	if configured_range != null:
		var c_mining: C_MiningProfile = entity.get_component(C_MiningProfile) as C_MiningProfile
		if c_mining:
			c_mining.mining_radius = maxf(float(configured_range), 0.0)


func _on_minerals_extracted(_amount: int) -> void:
	_fire_mining_beam()


func _fire_mining_beam() -> void:
	_beam_visible_timer = BEAM_VISIBLE_DURATION
	var entity: Node = _get_entity()
	if entity:
		var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
		if render_manager:
			render_manager.call("pulse_structure", entity, 0.18)
	if _mining_beam:
		_mining_beam.visible = true
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0
			mat.albedo_color.a = 1.0


func _create_mining_beam() -> void:
	_mining_beam = MeshInstance3D.new()

	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = 1.0
	_mining_beam.mesh = cylinder

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.3, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.2)
	material.emission_energy_multiplier = 5.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mining_beam.material_override = material

	_mining_beam.visible = false
	add_child(_mining_beam)


func update_mining_beam(delta: float) -> void:
	if not _mining_beam:
		return

	var entity: Node = _get_entity()
	if not entity:
		return

	# Update visibility timer
	if _beam_visible_timer > 0:
		_beam_visible_timer -= delta
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			var fade_progress: float = _beam_visible_timer / BEAM_VISIBLE_DURATION
			mat.emission_energy_multiplier = 5.0 * fade_progress
			mat.albedo_color.a = fade_progress
		if _beam_visible_timer <= 0:
			_mining_beam.visible = false
			return

		# Position beam during fade (need target from last mining)
		var c_mining: C_MiningProfile = entity.get_component(C_MiningProfile) as C_MiningProfile if entity.has_method("get_component") else null
		var target_asteroid: Node = null
		if c_mining and c_mining.target_asteroid_ref:
			var ref = c_mining.target_asteroid_ref.get_ref()
			target_asteroid = ref if ref is Node else null
		if target_asteroid and not target_asteroid.get("is_depleted"):
			var start_pos: Vector3 = entity.global_position + Vector3(0, 1.5, 0)
			var end_pos: Vector3 = target_asteroid.global_position
			var direction: Vector3 = end_pos - start_pos
			var distance: float = direction.length()
			if distance >= 0.1:
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
	else:
		_mining_beam.visible = false
