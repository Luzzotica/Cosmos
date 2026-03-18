extends System
class_name RepairRobotSystem
## Drives repair robot state machine: HEALING, FLY_TO_STATION, DOCKED_RECHARGING.
## Docking only at station for recharge; removes/restores C_RepairRobotMovement.
## Robots stay docked until there is a damaged structure to heal.

const C_RepairStationClass = preload("res://scripts/ecs/components/c_repair_station.gd")
const OBSTACLE_COLLISION_LAYER: int = 3


func query() -> QueryBuilder:
	return q.with_all([C_RepairRobotState, C_Transform3D, C_PhysicsBodyRef])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_state: C_RepairRobotState = entity.get_component(C_RepairRobotState) as C_RepairRobotState
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	if c_state == null or c_body_ref == null or c_body_ref.body == null:
		return
	var body: CharacterBody3D = c_body_ref.body

	match c_state.state:
		C_RepairRobotState.State.HEALING:
			_process_healing(entity, c_state, body)
		C_RepairRobotState.State.FLY_TO_STATION:
			_process_fly_to_station(entity, c_state, body)
		C_RepairRobotState.State.DOCKED_RECHARGING:
			_process_docked_recharging(entity, c_state, body, delta)


func _process_healing(entity: Entity, c_state: C_RepairRobotState, body: CharacterBody3D) -> void:
	if c_state.heals_remaining <= 0:
		_transition_to_fly_to_station(entity, c_state, body)
		body.set_collision_mask_value(OBSTACLE_COLLISION_LAYER, false)
		return

	var target_done: bool = false
	if not is_instance_valid(c_state.target_structure):
		c_state.target_structure = null
		target_done = true
	else:
		var c_health: C_Health = _get_health_from_node(c_state.target_structure)
		if c_health and c_health.current >= c_health.maximum:
			target_done = true

	if not target_done:
		return

	var c_station = _get_station(c_state)
	if c_station:
		var next_target: Node3D = c_station.peek_assignment()
		if next_target:
			c_state.target_structure = next_target
			var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
			if c_targeting:
				c_targeting.target_node = next_target
				c_targeting.target_position = Vector3.INF
			return

	_transition_to_fly_to_station(entity, c_state, body)
	body.set_collision_mask_value(OBSTACLE_COLLISION_LAYER, false)


func _process_fly_to_station(entity: Entity, c_state: C_RepairRobotState, body: CharacterBody3D) -> void:
	if c_state.source_station == null or not is_instance_valid(c_state.source_station):
		return
	var dock_pos: Vector3 = _get_dock_position(c_state.source_station as Node3D, c_state.dock_slot)
	var flat_diff: Vector3 = body.global_position - dock_pos
	flat_diff.y = 0.0
	var dist: float = flat_diff.length()
	if dist <= c_state.arrival_snap_epsilon:
		var c_movement: C_RepairRobotMovement = entity.get_component(C_RepairRobotMovement) as C_RepairRobotMovement
		if c_movement:
			c_state.parked_movement = c_movement
			entity.remove_component(C_RepairRobotMovement)
		body.velocity = Vector3.ZERO
		c_state.state = C_RepairRobotState.State.DOCKED_RECHARGING
		c_state.state_progress = 0.0
		c_state.target_structure = null
		var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
		if c_targeting:
			c_targeting.target_node = null
			c_targeting.target_position = Vector3.INF


func _process_docked_recharging(entity: Entity, c_state: C_RepairRobotState, body: CharacterBody3D, delta: float) -> void:
	c_state.state_progress += delta / maxf(c_state.recharge_duration, 0.001)
	c_state.state_progress = clampf(c_state.state_progress, 0.0, 1.0)
	if c_state.state_progress >= 1.0:
		var c_station = _get_station(c_state)
		var assignment: Node3D = c_station.peek_assignment() if c_station else null
		if assignment:
			body.set_collision_mask_value(OBSTACLE_COLLISION_LAYER, true)
			if c_state.parked_movement:
				entity.add_component(c_state.parked_movement)
				c_state.parked_movement = null
			c_state.heals_remaining = c_state.heals_max
			c_state.target_structure = assignment
			c_state.state = C_RepairRobotState.State.HEALING
			c_state.state_progress = 0.0
			var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
			if c_targeting:
				c_targeting.target_node = assignment
				c_targeting.target_position = Vector3.INF


func _transition_to_fly_to_station(entity: Entity, c_state: C_RepairRobotState, _body: CharacterBody3D) -> void:
	c_state.target_structure = null
	c_state.state = C_RepairRobotState.State.FLY_TO_STATION
	c_state.state_progress = 0.0
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	if c_targeting and c_state.source_station != null and is_instance_valid(c_state.source_station):
		var dock_pos: Vector3 = _get_dock_position(c_state.source_station as Node3D, c_state.dock_slot)
		c_targeting.target_node = null
		c_targeting.target_position = dock_pos


func _get_dock_position(structure_node: Node3D, slot: int) -> Vector3:
	var dock_name: String = "VisualRoot/DockPoint" + str(slot)
	var dock: Node3D = structure_node.get_node_or_null(dock_name) as Node3D
	if dock and dock.is_inside_tree():
		return dock.global_position
	return structure_node.global_position + Vector3.UP * 0.4


func _get_station(c_state: C_RepairRobotState) -> C_RepairStation:
	if c_state.source_station_entity == null or not is_instance_valid(c_state.source_station_entity):
		return null
	return c_state.source_station_entity.get_component(C_RepairStationClass) as C_RepairStation


func _get_health_from_node(target: Node) -> C_Health:
	var n: Node = target
	while n:
		if n.has_method("get_component"):
			var c: C_Health = n.get_component(C_Health) as C_Health
			if c:
				return c
		n = n.get_parent()
	return null
