extends Entity
class_name StructureEntity
## ECS entity for structures. Uses define_components() (GECS best practice).
## Parent must be a BaseStructure; components are built from parent's building_type, spawned_structure, etc.

func define_components() -> Array:
	var structure: BaseStructure = get_parent() as BaseStructure
	if structure == null:
		push_error("StructureEntity parent must be BaseStructure")
		return []

	var build_data: Resource = BuildManager.get_building_data(structure.building_type) if BuildManager else null
	var spawned: bool = structure.spawned_structure

	# Common components
	var c_structure: C_Structure = C_Structure.new()
	c_structure.structure_node = structure
	c_structure.building_type = structure.building_type
	c_structure.is_destroyed = structure.is_destroyed

	var max_health_val: float = 100.0
	if build_data and build_data.get("max_health") != null:
		max_health_val = float(build_data.max_health)
	var c_health: C_Health = C_Health.new()
	c_health.maximum = max_health_val
	c_health.current = max_health_val

	var c_team: C_Team = C_Team.new()
	c_team.team = "player"

	var c_transform: C_Transform3D = C_Transform3D.new()
	c_transform.position = structure.global_position
	c_transform.rotation = structure.rotation

	var c_construction: C_Construction = C_Construction.new()
	var construction_time_val: float = 3.0
	if build_data and build_data.get("construction_time") != null:
		construction_time_val = float(build_data.construction_time)
	c_construction.construction_time = construction_time_val
	c_construction.requires_power = true
	c_construction.build_power_cost = 10.0
	c_construction.instant_build = spawned
	c_construction.is_built = false
	c_construction.build_progress = 0.0

	var components: Array = [c_structure, c_health, c_team, c_transform, c_construction]
	components.append_array(_build_power_components(structure, build_data))
	components.append_array(structure._get_extra_ecs_components())
	return components


func _build_power_components(structure: BaseStructure, build_data: Resource) -> Array:
	var arr: Array = []
	var c_power_node: C_PowerNode = C_PowerNode.new()
	c_power_node.structure_node = structure
	c_power_node.max_connection_distance = PowerConstants.CONNECTION_RANGE
	c_power_node.max_connections = 4
	if build_data and build_data.get("max_connections") != null:
		c_power_node.max_connections = int(build_data.max_connections)
	c_power_node.is_enabled = true  # Enabled so graph sees it; C_ConstructionPowerNode overrides max_connections to 1

	var c_build_node: C_ConstructionPowerNode = C_ConstructionPowerNode.new()
	c_build_node.structure_node = structure
	c_build_node.max_connection_distance = PowerConstants.CONNECTION_RANGE
	c_build_node.saved_max_connections = c_power_node.max_connections
	c_build_node._apply_construction_mode(c_power_node)
	arr.append(c_build_node)
	var c_user: C_PowerUser = C_PowerUser.new()
	c_user.structure_node = structure
	c_user.is_construction_user = true
	c_user.use_power_cost = 10.0
	c_user.buffer_capacity = 15.0
	arr.append(c_user)

	var extras: Array = structure._get_structure_type_components(c_power_node, build_data)
	arr.append_array(extras)
	arr.insert(0, c_power_node)
	return arr


func on_ready() -> void:
	pass
