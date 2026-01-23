extends BaseStructure
class_name MiningStation
## Mining Station - Extracts minerals from nearby asteroids

signal mining_started(asteroid: Asteroid)
signal mining_stopped
signal minerals_extracted(amount: int)

@export var mining_radius: float = 12.5
@export var mining_interval: float = 3.0
@export var mine_amount: float = 5.0

var power_user: PowerUser
var target_asteroid: Asteroid = null
var _mining_timer: float = 0.0
var _is_mining: bool = false

# Mining beam visual
var _mining_beam: MeshInstance3D = null
var _beam_visible_timer: float = 0.0
const BEAM_VISIBLE_DURATION: float = 0.5  # How long the beam stays visible after firing
const BEAM_FADE_SPEED: float = 4.0  # How fast the beam fades out


func _ready() -> void:
	building_type = "mining_station"
	super._ready()
	_setup_power_user()
	_create_mining_beam()


func _setup_power_user() -> void:
	if power_node:
		for child in power_node.get_children():
			if child is PowerUser:
				power_user = child
				break


func _process(delta: float) -> void:
	if not is_built():
		_update_mining_beam(delta)
		return
	
	# Find target asteroid if we don't have one
	if target_asteroid == null or target_asteroid.is_depleted:
		_find_nearest_asteroid()
	
	if target_asteroid == null:
		_is_mining = false
		_update_mining_beam(delta)
		return
	
	# Update mining timer
	_mining_timer += delta
	
	if _mining_timer >= mining_interval:
		_mining_timer = 0.0
		_try_mine()
	
	# Update mining beam visual
	_update_mining_beam(delta)


func _try_mine() -> void:
	if not power_user:
		_is_mining = false
		return
	
	# Check if we have power
	if power_user.consume_power():
		if target_asteroid and not target_asteroid.is_depleted:
			_is_mining = true
			var mined: int = target_asteroid.mine_minerals(int(mine_amount))
			if mined > 0:
				GameState.add_minerals(mined)
				minerals_extracted.emit(mined)
				
				# Trigger mining beam burst
				_fire_mining_beam()
				
				# Trigger impact effect on asteroid
				if target_asteroid.has_method("show_mining_impact"):
					target_asteroid.show_mining_impact()
				
				if target_asteroid.is_depleted:
					target_asteroid = null
					_find_nearest_asteroid()
		else:
			_is_mining = false
	else:
		_is_mining = false


## Fire the mining beam (burst effect)
func _fire_mining_beam() -> void:
	_beam_visible_timer = BEAM_VISIBLE_DURATION
	if _mining_beam:
		_mining_beam.visible = true
		# Reset beam to full brightness
		var mat: StandardMaterial3D = _mining_beam.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0
			mat.albedo_color.a = 1.0


func _find_nearest_asteroid() -> void:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return
	
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if not asteroids_parent:
		return
	
	var closest_distance: float = INF
	var closest_asteroid: Asteroid = null
	
	for child in asteroids_parent.get_children():
		if child is Asteroid and not child.is_depleted:
			var distance: float = global_position.distance_to(child.global_position)
			if distance <= mining_radius and distance < closest_distance:
				closest_distance = distance
				closest_asteroid = child
	
	if closest_asteroid != target_asteroid:
		target_asteroid = closest_asteroid
		if target_asteroid:
			mining_started.emit(target_asteroid)
		else:
			mining_stopped.emit()


## Check if currently mining
func is_mining() -> bool:
	return _is_mining and power_user and power_user.has_power


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
