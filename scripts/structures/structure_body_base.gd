extends Node3D
class_name StructureBodyBase
## Thin proxy for ECS structure bodies. Forwards damage to parent Entity's C_Health.
## Mirrors EnemyShipBase: parent is StructureEntity; this holds meshes, PowerNode, SelectableComponent.

const C_BeamWeaponClass = preload("res://scripts/ecs/components/c_beam_weapon.gd")
const C_ConstructionClass = preload("res://scripts/ecs/components/c_construction.gd")
const C_MiningStationClass = preload("res://scripts/ecs/components/c_mining_station.gd")
const C_MonolithChargeClass = preload("res://scripts/ecs/components/c_monolith_charge.gd")

@export var placement_preview_include_mesh_names: PackedStringArray = PackedStringArray()
@export var placement_preview_exclude_mesh_names: PackedStringArray = PackedStringArray()

var is_destroyed: bool:
	get:
		var c: C_Structure = _get_component(C_Structure)
		return c != null and c.is_destroyed

var power_node: PowerNode = null
@onready var visual_handler: Node = get_node_or_null("VisualHandler")


func _ready() -> void:
	for child in get_children():
		if child is PowerNode:
			power_node = child
			break


func take_damage_event(event_payload: Dictionary) -> float:
	var c_health: C_Health = _get_component(C_Health)
	if c_health == null:
		return 0.0
	return c_health.take_damage_event(event_payload)


func take_damage(amount: float) -> void:
	take_damage_event({"amount": amount, "damage_type": "generic"})


func get_selection_name() -> String:
	var c_structure: C_Structure = _get_component(C_Structure)
	if c_structure and c_structure.building_type != "":
		return c_structure.building_type.replace("_", " ").capitalize()
	return name.replace("_", " ").capitalize()


func get_selection_details() -> Dictionary:
	var c_structure: C_Structure = _get_component(C_Structure)
	var c_health: C_Health = _get_component(C_Health)
	var c_team: C_Team = _get_component(C_Team)
	var c_construction: C_Construction = _get_component(C_Construction)
	var c_weapon = _get_component(C_BeamWeaponClass)
	var c_mining = _get_component(C_MiningStationClass)
	var c_charge = _get_component(C_MonolithChargeClass)
	var building_type: String = c_structure.building_type if c_structure else ""
	var built: bool = c_construction.is_built if c_construction else true
	var faction: String = c_team.team if c_team else "player"
	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "structure",
		"faction": faction,
		"building_type": building_type,
		"is_built": built,
		"stats": []
	}
	if c_health:
		details["health_current"] = c_health.current
		details["health_max"] = c_health.maximum
	if c_construction and not c_construction.is_built:
		details["build_progress"] = c_construction.build_progress * 100.0
	if power_node:
		details["is_powered"] = has_operational_power()
		details["is_connected"] = power_node.connected_nodes.size() > 0
		details["connection_count"] = power_node.connected_nodes.size()
	var stats: Array[Dictionary] = []
	stats.append({"label": "Type", "value": building_type.replace("_", " ").capitalize() if building_type else "Structure"})
	stats.append({"label": "Status", "value": "Operational" if built else "Building %.0f%%" % details.get("build_progress", 0.0)})
	if details.has("is_powered"):
		stats.append({"label": "Power", "value": "Online" if details.is_powered else "Offline"})
	if details.has("is_connected"):
		stats.append({"label": "Grid Link", "value": "Connected" if details.is_connected else "Disconnected"})
	if details.has("connection_count"):
		stats.append({"label": "Connections", "value": str(details.connection_count)})
	if c_weapon != null:
		stats.append({"label": "Range", "value": "%.0f" % c_weapon.attack_range})
		var rate: float = 1.0 / c_weapon.attack_cooldown if c_weapon.attack_cooldown > 0.0 else 0.0
		stats.append({"label": "Fire Rate", "value": "%.1f/s" % rate})
		stats.append({"label": "Damage", "value": "%.0f" % c_weapon.damage})
	if c_mining:
		stats.append({"label": "Mining Radius", "value": "%.1f" % c_mining.mining_radius})
		stats.append({"label": "Mine Amount", "value": "%.0f" % c_mining.mine_amount})
	if c_charge:
		stats.append({"label": "Charge", "value": "%.0f / %.0f" % [c_charge.current_charge, c_charge.power_required]})
	details["stats"] = stats
	return details


func on_deselected() -> void:
	pass


func initialize_visuals(entity: Node) -> void:
	if visual_handler and visual_handler.has_method("init"):
		visual_handler.init(entity)


func get_power_user() -> PowerUser:
	if power_node == null:
		return null
	for child in power_node.get_children():
		if child is PowerUser and not (child as PowerUser).is_construction_user:
			return child as PowerUser
	return null


func consume_power_for_attack() -> bool:
	var pu: PowerUser = get_power_user()
	if pu == null:
		return true
	return pu.consume_power()


func fire_mining_beam() -> void:
	if visual_handler and visual_handler.has_method("fire_mining_beam"):
		visual_handler.call("fire_mining_beam")


func has_operational_power() -> bool:
	if not is_built():
		return false
	var c_structure: C_Structure = _get_component(C_Structure)
	if c_structure and c_structure.building_type == "solar_panel":
		return true
	if power_node == null:
		return true
	if not power_node.is_enabled:
		return false
	if not has_node("/root/PowerGraphManager"):
		return power_node.connected_nodes.size() > 0
	var graph_manager: Node = get_node_or_null("/root/PowerGraphManager")
	if graph_manager == null or not graph_manager.has_method("find_subgraph_for_node"):
		return power_node.connected_nodes.size() > 0
	var subgraph: Variant = graph_manager.call("find_subgraph_for_node", power_node)
	if subgraph == null:
		return false
	var current_power: Variant = subgraph.get("power_current")
	if current_power != null:
		return float(current_power) > 0.0
	return power_node.connected_nodes.size() > 0


func is_built() -> bool:
	var c_construction: C_Construction = _get_component(C_Construction)
	return c_construction == null or c_construction.is_built


func get_team() -> String:
	var c_team: C_Team = _get_component(C_Team)
	return c_team.team if c_team else "player"


func set_starter_panel(is_starter: bool) -> void:
	if not is_starter:
		return
	var construction_component: ConstructionComponent = get_node_or_null("ConstructionComponent") as ConstructionComponent
	if construction_component:
		construction_component.set_built()
	if power_node:
		power_node.is_enabled = true
	var c_structure: C_Structure = _get_component(C_Structure)
	if c_structure and c_structure.building_type == "solar_panel":
		var power_source: PowerSource = power_node.get_node_or_null("PowerSource") as PowerSource
		if power_source:
			power_source.current_storage = power_source.max_storage * 0.5
	var entity: Node = get_parent()
	if entity and entity.has_method("remove_component"):
		entity.remove_component(C_ConstructionClass)
	var vh: Node = get_node_or_null("VisualHandler")
	if vh and vh.has_method("_on_construction_completed"):
		vh.call("_on_construction_completed")


func _get_component(component_class: Variant) -> Variant:
	var entity: Node = get_parent()
	if entity and entity.has_method("get_component"):
		return entity.get_component(component_class)
	return null
