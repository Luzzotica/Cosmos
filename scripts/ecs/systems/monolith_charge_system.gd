extends System
class_name MonolithChargeSystem
## Charges monoliths from the power grid. Each frame, built monoliths draw power
## via PowerGraphManager and add it to current_charge until power_required is met.

const C_MonolithChargeClass = preload("res://scripts/ecs/components/c_monolith_charge.gd")

func query() -> QueryBuilder:
	return q.with_all([C_MonolithChargeClass, C_Structure]).with_none([C_Construction])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	if not PowerGraphManager:
		return
	for entity in entities:
		_process_monolith(entity, delta)


func _process_monolith(entity: Entity, delta: float) -> void:
	var c_charge = entity.get_component(C_MonolithChargeClass)
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_charge == null or c_structure == null:
		return
	if c_charge.current_charge >= c_charge.power_required:
		return
	if c_structure.is_destroyed:
		return

	var structure_node: Node = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return

	var power_node: Node = structure_node.get_node_or_null("PowerNode")
	if power_node == null:
		return

	var charge_sink: Node3D = power_node.get_node_or_null("ChargeSink")
	if charge_sink == null or not charge_sink is Node3D:
		return

	var amount_to_draw: float = c_charge.base_absorption_rate * delta
	var room: float = c_charge.power_required - c_charge.current_charge
	amount_to_draw = minf(amount_to_draw, room)
	if amount_to_draw <= 0:
		return

	var drawn: float = PowerGraphManager.draw_power_for_user(charge_sink as Node3D, amount_to_draw)
	if drawn > 0:
		c_charge.current_charge = minf(c_charge.current_charge + drawn, c_charge.power_required)
