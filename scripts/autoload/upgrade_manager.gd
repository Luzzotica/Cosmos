extends Node
## UpgradeManager Singleton - Loads upgrade trees, checks availability,
## starts upgrades, and applies stat modifiers to live ECS components.

const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")
const C_StructureScript = preload("res://scripts/ecs/components/c_structure.gd")
const UpgradeTreeDataScript = preload("res://scripts/data/upgrade_tree_data.gd")
const UpgradeNodeDataScript = preload("res://scripts/data/upgrade_node_data.gd")

var _trees: Dictionary = {}


func _ready() -> void:
	_load_all_trees()


func _load_all_trees() -> void:
	var dir := DirAccess.open("res://resources/upgrades")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := "res://resources/upgrades/" + file_name
			var res: Resource = load(path)
			if res and res.get_script() == UpgradeTreeDataScript:
				_trees[res.tree_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()


func get_tree_for_building(building_type: String) -> Resource:
	return _trees.get(building_type, null)


func get_node_data(tree: Resource, upgrade_id: String) -> Resource:
	if tree == null:
		return null
	for node_data in tree.nodes:
		if node_data.id == upgrade_id:
			return node_data
	return null


func get_available_upgrades(entity: Entity) -> Array:
	var result: Array = []
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades == null:
		return result
	var tree: Resource = get_tree_for_building(c_upgrades.upgrade_tree_id)
	if tree == null:
		return result

	for node_data in tree.nodes:
		if c_upgrades.purchased_upgrades.has(node_data.id):
			continue
		if c_upgrades.is_upgrading:
			continue

		var prereqs_met := true
		for req_id in node_data.requires:
			if not c_upgrades.purchased_upgrades.has(req_id):
				prereqs_met = false
				break
		if not prereqs_met:
			continue

		var excluded := false
		for excl_id in node_data.excludes:
			if c_upgrades.purchased_upgrades.has(excl_id):
				excluded = true
				break
		if excluded:
			continue

		result.append(node_data)
	return result


func can_afford(node_data: Resource) -> bool:
	if node_data == null:
		return false
	return GameState.minerals >= node_data.mineral_cost


func start_upgrade(entity: Entity, upgrade_id: String) -> bool:
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades == null or c_upgrades.is_upgrading:
		return false

	var tree: Resource = get_tree_for_building(c_upgrades.upgrade_tree_id)
	if tree == null:
		return false

	var node_data: Resource = get_node_data(tree, upgrade_id)
	if node_data == null:
		return false

	if not can_afford(node_data):
		return false

	GameState.consume_minerals(node_data.mineral_cost)
	c_upgrades.is_upgrading = true
	c_upgrades.current_upgrade_id = upgrade_id
	c_upgrades.upgrade_progress = 0.0
	c_upgrades.upgrade_power_paid = 0.0
	return true


func apply_modifiers(entity: Entity, node_data: Resource) -> void:
	if node_data == null:
		return
	for mod in node_data.stat_modifiers:
		var comp_name: String = mod.get("component", "")
		var prop_name: String = mod.get("property", "")
		var operation: String = mod.get("operation", "")
		var value = mod.get("value", 0.0)

		var target_comp: Component = _find_component_by_name(entity, comp_name)
		if target_comp == null:
			continue

		var current = target_comp.get(prop_name)
		if current == null and operation != "set":
			continue

		match operation:
			"add":
				target_comp.set(prop_name, current + value)
			"multiply":
				target_comp.set(prop_name, current * value)
			"set":
				target_comp.set(prop_name, value)


func _find_component_by_name(entity: Entity, comp_class_name: String) -> Component:
	for key in entity.components:
		var comp: Component = entity.components[key]
		if comp.get_script() and comp.get_script().get_global_name() == comp_class_name:
			return comp
	return null
