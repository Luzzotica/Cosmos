extends System
class_name RepairRobotTargetingSystem
## Keeps targeting in sync with the locked target from the repair queue.
## Does NOT re-scan for targets; assignments come from RepairRobotSystem via the station queue.

const C_RepairRobotStateClass = preload("res://scripts/ecs/components/c_repair_robot_state.gd")


func query() -> QueryBuilder:
	return q.with_all([C_RepairRobotStateClass, C_Targeting])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, _delta: float) -> void:
	var c_state = entity.get_component(C_RepairRobotStateClass) as C_RepairRobotState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	if c_state == null or c_targeting == null:
		return
	if c_state.source_station == null or not is_instance_valid(c_state.source_station):
		return

	var dock_pos: Vector3 = _get_dock_position(c_state.source_station as Node3D, c_state.dock_slot)

	match c_state.state:
		C_RepairRobotState.State.HEALING:
			if is_instance_valid(c_state.target_structure):
				c_targeting.target_node = c_state.target_structure
				c_targeting.target_position = Vector3.INF
			else:
				c_state.target_structure = null
				c_targeting.target_node = null
				c_targeting.target_position = dock_pos
		C_RepairRobotState.State.FLY_TO_STATION:
			c_targeting.target_node = null
			c_targeting.target_position = dock_pos


func _get_dock_position(structure_node: Node3D, slot: int) -> Vector3:
	var dock_name: String = "VisualRoot/DockPoint" + str(slot)
	var dock: Node3D = structure_node.get_node_or_null(dock_name) as Node3D
	if dock and dock.is_inside_tree():
		return dock.global_position
	return structure_node.global_position + Vector3.UP * 0.4
