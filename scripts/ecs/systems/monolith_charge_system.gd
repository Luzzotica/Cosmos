extends System
class_name MonolithChargeSystem
## Draws power with diminishing returns for monolith charging.

func query() -> QueryBuilder:
	return q.with_all([C_MonolithCharge, C_PowerNode, C_Structure])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	if not ECS or not ECS.world:
		return

	for entity in entities:
		var c_charge: C_MonolithCharge = entity.get_component(C_MonolithCharge) as C_MonolithCharge
		var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
		if c_charge == null or c_power_node == null:
			continue
		if c_charge.power_required <= 0 or c_charge.absorbed >= c_charge.power_required:
			continue

		var fill_ratio: float = c_charge.absorbed / c_charge.power_required
		var efficiency: float = pow(1.0 - fill_ratio, c_charge.curve_exponent)
		var requested: float = c_charge.base_absorption_rate * delta

		var drawn: float = PowerGraph.draw_power(entity.get_instance_id(), requested)
		var effective_gain: float = drawn * efficiency
		c_charge.absorbed = minf(c_charge.absorbed + effective_gain, c_charge.power_required)

		if c_charge.absorbed >= c_charge.power_required:
			var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
			if c_structure and c_structure.structure_node and c_structure.structure_node.has_signal("fully_charged"):
				c_structure.structure_node.fully_charged.emit()
