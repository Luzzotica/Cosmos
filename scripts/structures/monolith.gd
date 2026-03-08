extends BaseStructure
class_name Monolith
## Monolith - Absorbs power from the grid. Map-placed objective structure.
## Uses exponential diminishing returns; reaching 100% charge is extremely challenging.

func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.LEAF
	var c_charge: C_MonolithCharge = C_MonolithCharge.new()
	c_charge.structure_node = self
	if _pending_monolith_power_required > 0:
		c_charge.power_required = _pending_monolith_power_required
	return [c_charge]


func _ready() -> void:
	building_type = "monolith"
	super._ready()


func get_charge_percentage() -> float:
	if _ecs_entity:
		var c_charge: C_MonolithCharge = _ecs_entity.get_component(C_MonolithCharge) as C_MonolithCharge
		if c_charge:
			return c_charge.get_charge_percentage()
	return 0.0


func is_fully_charged() -> bool:
	if _ecs_entity:
		var c_charge: C_MonolithCharge = _ecs_entity.get_component(C_MonolithCharge) as C_MonolithCharge
		if c_charge:
			return c_charge.is_fully_charged()
	return false
