extends System
class_name ConstructionSystem
## Ticks build progress for structures. Consumes construction power from C_PowerUser.
## Replaces ConstructionComponent._process logic.

func _ready() -> void:
	process_empty = true


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_Construction, C_ConstructionPowerNode, C_PowerNode])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	var c_build_node: C_ConstructionPowerNode = entity.get_component(C_ConstructionPowerNode) as C_ConstructionPowerNode
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_structure == null or c_construction == null or c_build_node == null or c_power_node == null or c_construction.is_built:
		return

	if c_construction.instant_build:
		_complete_construction(entity, c_construction, c_structure, c_power_node, c_build_node)
		return

	# All buildings require power during construction (no exceptions)
	if c_construction.build_power_paid:
		c_construction.build_progress += delta / maxf(c_construction.construction_time, 0.001)
		c_construction.build_progress = clampf(c_construction.build_progress, 0.0, 1.0)
		if c_construction.build_progress >= 1.0:
			_complete_construction(entity, c_construction, c_structure, c_power_node, c_build_node)
		
		return
	
	if c_construction.requires_power:
		if c_power_node.connected_entity_ids.size() > 0:
			# Need to pay power cost - draw on demand, then consume
			var _drawn: float = PowerGraph.draw_power_for_user_entity(entity, c_construction.build_power_cost)
			if _drawn >= c_construction.build_power_cost:
				c_construction.build_power_paid = true
	else:
		# No power required - can build immediately
		c_construction.build_power_paid = true


func _complete_construction(entity: Entity, c_construction: C_Construction, c_structure: C_Structure, c_power_node: C_PowerNode, c_construction_node: C_ConstructionPowerNode) -> void:
	c_construction.build_progress = 1.0
	c_construction.build_power_paid = true
	c_construction.is_built = true
	c_power_node.is_enabled = true

	# Restore max_connections so refresh_graph will compute and create the preview connections as real edges
	c_power_node.max_connections = c_construction_node.saved_max_connections

	# Remove construction components
	entity.remove_component(C_Construction)
	entity.remove_component(C_ConstructionPowerNode)

	# Full refresh recomputes connections from geometry and creates C_PowerEdge entities for new connections
	var world: Node = ECS.world if ECS else null
	if PowerGraph and world:
		PowerGraph.refresh_graph(world)

	# Notify structure for visuals
	if c_structure and c_structure.structure_node:
		var structure: Node = c_structure.structure_node
		if structure.has_method("_on_construction_completed"):
			structure.call("_on_construction_completed")
