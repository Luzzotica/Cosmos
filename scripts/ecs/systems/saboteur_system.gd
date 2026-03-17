extends System
class_name SaboteurSystem
## Drives saboteur state machine: MOVE_TO, POWERING_UP, BLOCKING, POWERING_DOWN.
## Adds/removes C_SaboteurMovement by state; enables/disables barrier for power line blocking.


const POWER_LINE_LAYER: int = 20


func query() -> QueryBuilder:
	return q.with_all([C_SaboteurState, C_Transform3D, C_PhysicsBodyRef, C_Targeting])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_saboteur: C_SaboteurState = entity.get_component(C_SaboteurState) as C_SaboteurState
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	if c_saboteur == null or c_body_ref == null or c_body_ref.body == null:
		return
	var body: CharacterBody3D = c_body_ref.body

	match c_saboteur.state:
		C_SaboteurState.State.MOVE_TO:
			_process_move_to(entity, c_saboteur, body)
		C_SaboteurState.State.POWERING_UP:
			_process_powering_up(entity, c_saboteur, body, delta)
		C_SaboteurState.State.BLOCKING:
			_process_blocking(entity, c_saboteur, body)
		C_SaboteurState.State.POWERING_DOWN:
			_process_powering_down(entity, c_saboteur, body, delta)


func _process_move_to(entity: Entity, c_saboteur: C_SaboteurState, body: CharacterBody3D) -> void:
	var dist: float
	var line_start: Vector3 = c_saboteur.target_line_start
	var line_end: Vector3 = c_saboteur.target_line_end
	if line_start.distance_squared_to(line_end) > 0.001:
		dist = _distance_to_segment(body.global_position, line_start, line_end)
	else:
		dist = body.global_position.distance_to(c_saboteur.hover_position)
	if dist > c_saboteur.arrival_range:
		return
	# Transition to POWERING_UP: remove C_SaboteurMovement, zero velocity
	var c_movement: C_SaboteurMovement = entity.get_component(C_SaboteurMovement) as C_SaboteurMovement
	if c_movement:
		c_saboteur.parked_movement = c_movement
		entity.remove_component(C_SaboteurMovement)
	body.velocity = Vector3.ZERO
	c_saboteur.state = C_SaboteurState.State.POWERING_UP
	c_saboteur.state_progress = 0.0
	c_saboteur.emit_signal("state_changed", c_saboteur.state, c_saboteur.state_progress)


func _process_powering_up(entity: Entity, c_saboteur: C_SaboteurState, body: CharacterBody3D, delta: float) -> void:
	c_saboteur.state_progress += delta / maxf(c_saboteur.power_up_duration, 0.001)
	c_saboteur.state_progress = clampf(c_saboteur.state_progress, 0.0, 1.0)
	c_saboteur.emit_signal("state_changed", c_saboteur.state, c_saboteur.state_progress)
	if c_saboteur.state_progress >= 1.0:
		c_saboteur.state = C_SaboteurState.State.BLOCKING
		c_saboteur.emit_signal("state_changed", c_saboteur.state, 1.0)
		_set_barrier_active(body, true)


func _process_blocking(entity: Entity, c_saboteur: C_SaboteurState, body: CharacterBody3D) -> void:
	var target: Node3D = c_saboteur.target_structure
	if target != null and is_instance_valid(target) and target.get("is_destroyed") != true:
		return
	# Target died or invalid -> POWERING_DOWN
	_set_barrier_active(body, false)
	c_saboteur.state = C_SaboteurState.State.POWERING_DOWN
	c_saboteur.state_progress = 0.0
	c_saboteur.emit_signal("state_changed", c_saboteur.state, c_saboteur.state_progress)


func _process_powering_down(entity: Entity, c_saboteur: C_SaboteurState, body: CharacterBody3D, delta: float) -> void:
	c_saboteur.state_progress += delta / maxf(c_saboteur.power_down_duration, 0.001)
	c_saboteur.state_progress = clampf(c_saboteur.state_progress, 0.0, 1.0)
	c_saboteur.emit_signal("state_changed", c_saboteur.state, c_saboteur.state_progress)
	if c_saboteur.state_progress >= 1.0:
		# Transition to MOVE_TO: add C_SaboteurMovement back, clear target for retarget
		if c_saboteur.parked_movement:
			entity.add_component(c_saboteur.parked_movement)
			c_saboteur.parked_movement = null
		c_saboteur.target_structure = null
		c_saboteur.hover_position = Vector3.ZERO
		c_saboteur.target_line_start = Vector3.ZERO
		c_saboteur.target_line_end = Vector3.ZERO
		var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
		if c_targeting:
			c_targeting.target_node = null
			c_targeting.target_position = Vector3.INF
		c_saboteur.state = C_SaboteurState.State.MOVE_TO
		c_saboteur.state_progress = 0.0
		c_saboteur.emit_signal("state_changed", c_saboteur.state, c_saboteur.state_progress)


static func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var ap: Vector3 = p - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf(ap.dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector3 = a + t * ab
	return p.distance_to(closest)


func _set_barrier_active(body: CharacterBody3D, active: bool) -> void:
	var barrier: Node = body.get_node_or_null("Barrier")
	if barrier == null:
		return
	if barrier is CollisionObject3D:
		var co: CollisionObject3D = barrier as CollisionObject3D
		co.set_collision_layer_value(POWER_LINE_LAYER, active)
	if barrier.has_method("set_visible"):
		barrier.visible = active
	elif barrier is Node3D:
		barrier.visible = active
