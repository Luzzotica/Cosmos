extends BaseStructure
class_name MiningStation
## Mining Station - Extracts minerals from nearby asteroids

signal mining_started(asteroid: Asteroid)
signal mining_stopped
signal minerals_extracted(amount: int)

@export var mining_radius: float = 12.5
@export var mining_interval: float = 3.0
@export var mine_amount: float = 5.0

var target_asteroid: Asteroid = null
var _mining_timer: float = 0.0
var _is_mining: bool = false

# Mining beam visual
var _mining_beam: MeshInstance3D = null
var _beam_visible_timer: float = 0.0
const BEAM_VISIBLE_DURATION: float = 0.5  # How long the beam stays visible after firing
const BEAM_FADE_SPEED: float = 4.0  # How fast the beam fades out
var _last_powered_state: bool = true


func _ready() -> void:
	building_type = "mining_station"
	_apply_balance_data()
	super._ready()
	_last_powered_state = _get_has_power()
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", _last_powered_state)
	_create_mining_beam()


func _apply_balance_data() -> void:
	var data: Resource = BuildManager.get_building_data(building_type)
	if data == null:
		return
	var configured_range: Variant = data.get("action_range")
	if configured_range != null:
		mining_radius = maxf(float(configured_range), 0.0)


func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.LEAF
	var c_mining: C_MiningProfile = C_MiningProfile.new()
	if build_data:
		var r: Variant = build_data.get("action_range")
		if r != null:
			c_mining.mining_radius = float(r)
		var amt: Variant = build_data.get("mine_amount")
		if amt != null:
			c_mining.mine_amount = float(amt)
	return [c_mining]


func _get_has_power() -> bool:
	if _ecs_entity:
		var c_power_user: C_PowerUser = _ecs_entity.get_component(C_PowerUser) as C_PowerUser
		if c_power_user:
			return c_power_user.has_power()
	return false


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		_update_mining_beam(delta)
		return

	# ECS mode: MiningSystem handles mining; we sync target from C_MiningProfile for beam visual
	if _ecs_entity:
		var c_mining: C_MiningProfile = _ecs_entity.get_component(C_MiningProfile) as C_MiningProfile
		if c_mining and c_mining.target_asteroid_ref:
			var ref = c_mining.target_asteroid_ref.get_ref()
			target_asteroid = ref if ref is Asteroid else null
		else:
			target_asteroid = null
		_is_mining = _get_has_power() and target_asteroid != null and not target_asteroid.is_depleted
		var powered_now: bool = _get_has_power()
		if powered_now != _last_powered_state:
			_last_powered_state = powered_now
			if has_method("set_powered_visual_state"):
				call("set_powered_visual_state", powered_now)
		_update_mining_beam(delta)
		return
	
	_update_mining_beam(delta)


## Fire the mining beam (burst effect)
func _fire_mining_beam() -> void:
	_beam_visible_timer = BEAM_VISIBLE_DURATION
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager:
		render_manager.call("pulse_structure", self, 0.18)
	if _mining_beam:
		_mining_beam.visible = true
		# Reset beam to full brightness
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0
			mat.albedo_color.a = 1.0


## Check if currently mining
func is_mining() -> bool:
	return _is_mining and _get_has_power()


## Get the target asteroid position for beam rendering
func get_target_position() -> Vector3:
	if target_asteroid:
		return target_asteroid.global_position
	return global_position


## Create the mining beam visual
func _create_mining_beam() -> void:
	_mining_beam = MeshInstance3D.new()
	
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.15
	cylinder.bottom_radius = 0.15
	cylinder.height = 1.0  # Will be set dynamically
	_mining_beam.mesh = cylinder
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.3, 1.0)  # Bright yellow
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.2)
	material.emission_energy_multiplier = 5.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mining_beam.material_override = material
	
	_mining_beam.visible = false
	add_child(_mining_beam)


## Update the mining beam visual
func _update_mining_beam(delta: float) -> void:
	if not _mining_beam:
		return
	
	# Update visibility timer
	if _beam_visible_timer > 0:
		_beam_visible_timer -= delta
		
		# Fade out the beam
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			var fade_progress: float = _beam_visible_timer / BEAM_VISIBLE_DURATION
			mat.emission_energy_multiplier = 5.0 * fade_progress
			mat.albedo_color.a = fade_progress
		
		if _beam_visible_timer <= 0:
			_mining_beam.visible = false
			return
	else:
		_mining_beam.visible = false
		return
	
	# Only position the beam if we have a target
	if not target_asteroid:
		_mining_beam.visible = false
		return
	
	# Calculate beam position and rotation
	var start_pos: Vector3 = global_position + Vector3(0, 1.5, 0)  # Emit from top of station
	var end_pos: Vector3 = target_asteroid.global_position
	var direction: Vector3 = end_pos - start_pos
	var distance: float = direction.length()
	
	if distance < 0.1:
		_mining_beam.visible = false
		return
	
	# Position at midpoint
	var midpoint: Vector3 = (start_pos + end_pos) / 2.0
	_mining_beam.global_position = midpoint
	
	# Update cylinder height to match distance
	var cylinder_mesh: CylinderMesh = _mining_beam.mesh as CylinderMesh
	if cylinder_mesh:
		cylinder_mesh.height = distance
	
	# Reset rotation and calculate new orientation
	_mining_beam.rotation = Vector3.ZERO
	
	# Use look_at with rotation adjustment (same as power graph lines)
	direction = direction.normalized()
	var up: Vector3 = Vector3.UP
	if abs(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_mining_beam.look_at_from_position(midpoint, midpoint + direction, up)
	_mining_beam.rotate_object_local(Vector3(1, 0, 0), PI / 2)


func _play_sfx(sfx_id: String, volume_db: float = -6.0) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", sfx_id, volume_db)


