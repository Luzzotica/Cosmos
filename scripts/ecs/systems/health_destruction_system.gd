extends System
class_name HealthDestructionSystem
## When C_Health.current <= 0, marks destroyed and removes entity / frees structure.

func query() -> QueryBuilder:
	return q.with_all([C_Health, C_Structure])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
		if c_health == null or c_structure == null:
			continue
		if c_health.current > 0:
			continue
		if c_structure.is_destroyed:
			continue

		c_structure.is_destroyed = true
		var structure_node: Node = c_structure.structure_node
		if structure_node and is_instance_valid(structure_node):
			if structure_node.has_signal("destroyed"):
				structure_node.destroyed.emit()
			structure_node.queue_free()
		if ECS and ECS.world:
			ECS.world.remove_entity(entity)
