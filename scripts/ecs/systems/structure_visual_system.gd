extends System
class_name StructureVisualSystem
## Updates powered visual state for built structures.
## Queries C_Structure entities and drives StructureBehavior.set_powered_visual_state.

func query() -> QueryBuilder:
	return q.with_all([C_Structure])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
		if c_construction != null and not c_construction.is_built:
			continue
		var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
		if c_structure == null or c_structure.structure_node == null:
			continue
		var structure_node: Node = c_structure.structure_node
		if not is_instance_valid(structure_node):
			continue
		var behavior: Node = structure_node.get_node_or_null("StructureBehavior")
		if behavior == null or not behavior.has_method("set_powered_visual_state"):
			continue
		var powered: bool = StructureEntityUtils.has_operational_power(structure_node)
		behavior.set_powered_visual_state(powered)
