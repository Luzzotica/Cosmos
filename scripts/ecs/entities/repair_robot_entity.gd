extends Entity
class_name RepairRobotEntity
## ECS entity for repair robots. Root is Entity; child is CharacterBody3D (RobotBody).

const C_RepairStationClass = preload("res://scripts/ecs/components/c_repair_station.gd")
const C_RepairRobotStateClass = preload("res://scripts/ecs/components/c_repair_robot_state.gd")


func define_components() -> Array:
	return []


func on_ready() -> void:
	var body: CharacterBody3D = _find_physics_body()
	if body:
		var c_ref: C_PhysicsBodyRef = get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_ref:
			c_ref.body = body
		var c_transform: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
		if c_transform:
			c_transform.position = body.global_position
			c_transform.rotation = body.rotation
		var c_targeting: C_Targeting = get_component(C_Targeting) as C_Targeting
		if c_targeting:
			c_targeting.fallback_position = body.global_position + Vector3.FORWARD * 8.0
			c_targeting.forward_direction = -body.global_basis.z
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health and not c_health.destroyed.is_connected(_on_health_destroyed):
		c_health.destroyed.connect(_on_health_destroyed)


func _find_physics_body() -> CharacterBody3D:
	var body: Node = get_node_or_null("RobotBody")
	if body is CharacterBody3D:
		return body as CharacterBody3D
	for child in get_children():
		if child is CharacterBody3D:
			return child as CharacterBody3D
	return null


func _on_health_destroyed() -> void:
	var c_state = get_component(C_RepairRobotStateClass) as C_RepairRobotState
	if c_state and c_state.source_station_entity:
		var c_station = c_state.source_station_entity.get_component(C_RepairStationClass) as C_RepairStation
		if c_station:
			c_station.robots_active = maxi(0, c_station.robots_active - 1)
			c_station.release_slot(c_state.dock_slot)
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
	else:
		queue_free()
