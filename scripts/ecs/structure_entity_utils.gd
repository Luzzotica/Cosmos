class_name StructureEntityUtils
extends RefCounted
## Static helpers for structure entity logic.
## Used by E_Structure and other structure entities.

static func is_built(entity: Node) -> bool:
	if not entity or not entity.has_method("get_component"):
		return true
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_construction:
		return c_construction.is_built
	return true


static func get_build_progress(entity: Node) -> float:
	if not entity or not entity.has_method("get_component"):
		return 1.0
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_construction:
		return c_construction.build_progress
	return 1.0


static func has_operational_power(entity: Node) -> bool:
	if not is_built(entity):
		return false
	if not entity or not entity.has_method("get_component"):
		return true
	# Producers (solar panels) are always online
	var c_power_source: C_PowerSource = entity.get_component(C_PowerSource) as C_PowerSource
	var c_power_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
	if c_power_source != null or c_power_gen != null:
		return true
	var c_power_user: C_PowerUser = entity.get_component(C_PowerUser) as C_PowerUser
	if c_power_user:
		return c_power_user.has_power()
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		if not c_power_node.is_enabled:
			return false
		if not PowerGraph:
			return c_power_node.connected_entity_ids.size() > 0
		var sg: Variant = PowerGraph.find_subgraph_for_entity(entity)
		if sg == null:
			return false
		return float(sg.power_current) > 0.0
	return true


static func take_damage(entity: Node, amount: float) -> void:
	if not entity or not entity.has_method("get_component"):
		return
	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	if c_health:
		c_health.current = maxf(0.0, c_health.current - amount)


static func take_damage_event(entity: Node, event_payload: Dictionary) -> float:
	if not entity or not entity.has_method("get_component"):
		return 0.0
	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	if c_health:
		var amount: float = float(event_payload.get("amount", 0.0))
		var dmg_type: String = String(event_payload.get("damage_type", "generic"))
		var multiplier: float = c_health.resistance_profile.get(dmg_type, 1.0) if c_health.resistance_profile else 1.0
		var actual: float = amount * multiplier
		c_health.current = maxf(0.0, c_health.current - actual)
		return actual
	return 0.0


static func can_accept_more_connections(entity: Node) -> bool:
	if not PowerGraph or not entity or not entity.has_method("get_component"):
		return false
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return PowerGraph.can_power_node_accept_more_connections(c_power_node)
	return false


static func get_node_type(entity: Node) -> int:
	if not entity or not entity.has_method("get_component"):
		return C_PowerNode.NodeType.SOURCE
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.node_type
	return C_PowerNode.NodeType.SOURCE


static func get_max_connection_distance(entity: Node) -> float:
	if not entity or not entity.has_method("get_component"):
		return PowerConstants.CONNECTION_RANGE
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.max_connection_distance
	return PowerConstants.CONNECTION_RANGE


static func can_connect_to(entity: Node, other: Node3D) -> bool:
	if other == entity:
		return false
	if other == null or not other.has_method("get_node_type"):
		return false
	if not can_accept_more_connections(entity):
		return false
	if not other.can_accept_more_connections():
		return false
	return true


static func connect_node(entity: Node, other: Node3D) -> void:
	if other == entity:
		return
	var other_entity: Node = other.get("_ecs_entity") if other.get("_ecs_entity") != null else other
	if not other_entity or not other_entity.has_method("get_component"):
		return
	var other_c_pn: C_PowerNode = other_entity.get_component(C_PowerNode) as C_PowerNode
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode if entity.has_method("get_component") else null
	if c_power_node and other_c_pn:
		var my_id: int = entity.get_instance_id()
		var other_id: int = other_entity.get_instance_id()
		if other_id not in c_power_node.connected_entity_ids:
			c_power_node.connected_entity_ids.append(other_id)
		if my_id not in other_c_pn.connected_entity_ids:
			other_c_pn.connected_entity_ids.append(my_id)


static func is_valid_connection_target(entity: Node) -> bool:
	if PowerGraph:
		return PowerGraph.is_entity_valid_connection_target(entity)
	return false


static func get_team(entity: Node) -> String:
	if not entity or not entity.has_method("get_component"):
		return "player"
	var c_team: C_Team = entity.get_component(C_Team) as C_Team
	if c_team:
		return c_team.team
	return "player"


static func get_selection_name(entity: Node, building_type: String) -> String:
	if building_type != "":
		return building_type.replace("_", " ").capitalize()
	return entity.name.replace("_", " ").capitalize() if entity else ""


static func get_selection_details(entity: Node, building_type: String, extra_stats: Array = []) -> Dictionary:
	var details: Dictionary = {
		"name": get_selection_name(entity, building_type),
		"category": "structure",
		"faction": get_team(entity),
		"building_type": building_type,
		"is_built": is_built(entity),
		"stats": []
	}
	if not entity or not entity.has_method("get_component"):
		return details

	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	if c_health:
		details["health_current"] = c_health.current
		details["health_max"] = c_health.maximum

	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_construction and not c_construction.is_built:
		details["build_progress"] = c_construction.build_progress * 100.0

	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		details["is_powered"] = has_operational_power(entity)
		details["is_connected"] = c_power_node.connected_entity_ids.size() > 0
		details["connection_count"] = c_power_node.connected_entity_ids.size()

	var c_power_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
	if c_power_gen:
		details["power_output"] = c_power_gen.power_output

	var c_monolith_charge: C_MonolithCharge = entity.get_component(C_MonolithCharge) as C_MonolithCharge
	if c_monolith_charge:
		details["charge_percent"] = c_monolith_charge.get_charge_percentage() * 100.0

	var c_turret: C_TurretProfile = entity.get_component(C_TurretProfile) as C_TurretProfile
	if c_turret:
		details["damage"] = c_turret.damage
		details["attack_range"] = c_turret.attack_range

	var stats: Array[Dictionary] = []
	stats.append({"label": "Type", "value": building_type.replace("_", " ").capitalize()})
	stats.append({"label": "Status", "value": "Operational" if details.is_built else "Building %.0f%%" % details.get("build_progress", 0.0)})
	if details.has("is_powered"):
		stats.append({"label": "Power", "value": "Online" if details.is_powered else "Offline"})
	if details.has("is_connected"):
		stats.append({"label": "Grid Link", "value": "Connected" if details.is_connected else "Disconnected"})
	if details.has("connection_count"):
		stats.append({"label": "Connections", "value": str(details.connection_count)})
	if details.has("power_output"):
		stats.append({"label": "Output", "value": str(int(details.power_output)) + " W"})
	if details.has("charge_percent"):
		stats.append({"label": "Charge", "value": "%.1f%%" % details.charge_percent})
	if details.has("damage"):
		stats.append({"label": "Damage", "value": str(int(details.damage))})
	if entity and entity.has_method("get_target"):
		var target: Variant = entity.get_target()
		var has_target: bool = target != null and (target is Node) and is_instance_valid(target as Node)
		stats.append({"label": "Target", "value": "Acquired" if has_target else "None"})

	for extra in extra_stats:
		if extra is Dictionary and extra.has("label") and extra.has("value"):
			stats.append(extra)

	details["stats"] = stats
	return details
