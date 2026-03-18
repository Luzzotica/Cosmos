extends CharacterBody3D
class_name EnemyShipBase
## Thin visual/physics proxy for ECS enemies.
## Proxies damage to parent Entity's C_Health and reads ECS components for selection UI.

const C_DestroyedClass = preload("res://scripts/ecs/components/c_destroyed.gd")
const C_BeamWeaponClass = preload("res://scripts/ecs/components/c_beam_weapon.gd")

var is_destroyed: bool:
	get:
		if _get_component(C_DestroyedClass) != null:
			return true
		var c: C_EnemyState = _get_component(C_EnemyState)
		return c != null and c.is_destroyed

var attack_range: float:
	get:
		var c_weapon = _get_component(C_BeamWeaponClass)
		if c_weapon:
			return maxf(float(c_weapon.get("attack_range")), 0.0)
		return 0.0

@onready var selectable_component: Node = get_node_or_null("SelectableComponent")
@onready var visual_handler: ShipVisualHandler = get_node_or_null("VisualHandler") as ShipVisualHandler


func take_damage_event(event_payload: Dictionary) -> float:
	var c_health: C_Health = _get_component(C_Health)
	if c_health == null:
		return 0.0
	return c_health.take_damage_event(event_payload)


func take_damage(amount: float) -> void:
	take_damage_event({"amount": amount, "damage_type": "generic"})


func get_selection_name() -> String:
	var c_state: C_EnemyState = _get_component(C_EnemyState)
	if c_state:
		return c_state.display_name
	return "Enemy Ship"


func get_selection_details() -> Dictionary:
	var c_state: C_EnemyState = _get_component(C_EnemyState)
	var c_health: C_Health = _get_component(C_Health)
	var c_team: C_Team = _get_component(C_Team)
	var c_weapon = _get_component(C_BeamWeaponClass)
	var faction: String = c_team.team if c_team else "enemy"
	var dmg: float = c_weapon.damage if c_weapon else 0.0
	var spd: float = c_state.speed if c_state else 0.0
	var resistances: Array[String] = []
	if c_health:
		for damage_type in c_health.resistance_profile.keys():
			var mult: float = float(c_health.resistance_profile[damage_type])
			if mult <= 0.0:
				resistances.append("%s Immune" % String(damage_type).capitalize())
			elif mult < 1.0:
				var reduced_pct: int = int(round((1.0 - mult) * 100.0))
				resistances.append("%s -%d%%" % [String(damage_type).capitalize(), reduced_pct])
	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "enemy",
		"faction": faction,
		"damage": dmg,
		"speed": spd,
		"stats": [
			{"label": "Damage", "value": "%.0f" % dmg},
			{"label": "Speed", "value": "%.1f" % spd}
		]
	}
	if not resistances.is_empty():
		details["stats"].append({"label": "Resists", "value": ", ".join(resistances)})
	if c_health:
		details["health_current"] = c_health.current
		details["health_max"] = c_health.maximum
	return details


func on_deselected() -> void:
	pass


func initialize_visuals(entity: Node) -> void:
	if visual_handler:
		visual_handler.init(entity)


func _get_component(component_class: Variant) -> Variant:
	var entity: Node = get_parent()
	if entity and entity.has_method("get_component"):
		return entity.get_component(component_class)
	return null
