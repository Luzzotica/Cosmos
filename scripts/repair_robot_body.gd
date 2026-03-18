extends CharacterBody3D
class_name RepairRobotBody
## Thin proxy for repair robot. Forwards damage to parent Entity's C_Health.
## No SelectableComponent - robots are not player-selectable.


func take_damage_event(event_payload: Dictionary) -> float:
	var c_health: C_Health = _get_component(C_Health)
	if c_health == null:
		return 0.0
	return c_health.take_damage_event(event_payload)


func take_damage(amount: float) -> void:
	take_damage_event({"amount": amount, "damage_type": "generic"})


func _get_component(component_class: Variant) -> Variant:
	var entity: Node = get_parent()
	if entity and entity.has_method("get_component"):
		return entity.get_component(component_class)
	return null
