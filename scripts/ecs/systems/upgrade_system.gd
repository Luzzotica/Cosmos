extends System
class_name UpgradeSystem
## Ticks upgrade progress for structures with an active upgrade.
## Draws power from the grid to pay the upgrade's power cost, then counts down
## the upgrade timer. On completion, applies stat modifiers via UpgradeManager.

const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")
const C_StructureScript = preload("res://scripts/ecs/components/c_structure.gd")
const UpgradeManagerScript = preload("res://scripts/autoload/upgrade_manager.gd")


func query() -> QueryBuilder:
	return q.with_all([C_UpgradesScript, C_StructureScript])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		_process_upgrade(entity, delta)


func _process_upgrade(entity: Entity, delta: float) -> void:
	var c_upgrades = entity.get_component(C_UpgradesScript)
	var c_structure = entity.get_component(C_StructureScript) as C_Structure
	if c_upgrades == null or c_structure == null:
		return
	if not c_upgrades.is_upgrading:
		return
	if c_structure.is_destroyed:
		c_upgrades.is_upgrading = false
		c_upgrades.current_upgrade_id = ""
		_complete_upgrade_visuals(c_structure)
		return

	if not c_upgrades._upgrade_visuals_started:
		c_upgrades._upgrade_visuals_started = true
		_start_upgrade_visuals(c_structure)

	var mgr: Node = Engine.get_singleton("UpgradeManager") if Engine.has_singleton("UpgradeManager") else null
	if mgr == null:
		mgr = _get_autoload("UpgradeManager")
	if mgr == null:
		return

	var tree: Resource = mgr.get_tree_for_building(c_upgrades.upgrade_tree_id)
	if tree == null:
		return
	var node_data: Resource = mgr.get_node_data(tree, c_upgrades.current_upgrade_id)
	if node_data == null:
		return

	if c_upgrades.upgrade_power_paid < node_data.power_cost:
		var still_needed: float = node_data.power_cost - c_upgrades.upgrade_power_paid
		var power_user: Node3D = _find_power_user(c_structure)
		if power_user and PowerGraphManager:
			var drawn: float = PowerGraphManager.draw_power_for_user(power_user, still_needed)
			c_upgrades.upgrade_power_paid += drawn
		return

	var time: float = maxf(node_data.upgrade_time, 0.01)
	c_upgrades.upgrade_progress += delta / time
	c_upgrades.upgrade_progress = clampf(c_upgrades.upgrade_progress, 0.0, 1.0)

	_update_upgrade_visuals(c_structure, c_upgrades.upgrade_progress)

	if c_upgrades.upgrade_progress >= 1.0:
		_complete_upgrade(entity, c_upgrades, node_data, mgr)


func _complete_upgrade(entity: Entity, c_upgrades, node_data: Resource, mgr: Node) -> void:
	var c_structure = entity.get_component(C_StructureScript) as C_Structure
	mgr.apply_modifiers(entity, node_data)
	c_upgrades.purchased_upgrades.append(c_upgrades.current_upgrade_id)
	c_upgrades.is_upgrading = false
	c_upgrades.current_upgrade_id = ""
	c_upgrades.upgrade_progress = 0.0
	c_upgrades.upgrade_power_paid = 0.0
	c_upgrades._upgrade_visuals_started = false
	if c_structure:
		_complete_upgrade_visuals(c_structure)


func _start_upgrade_visuals(c_structure: C_Structure) -> void:
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return
	var vh: Node = structure_node.get_node_or_null("VisualHandler")
	if vh and vh.has_method("start_upgrade_animation"):
		vh.call("start_upgrade_animation")


func _update_upgrade_visuals(c_structure: C_Structure, progress: float) -> void:
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return
	var vh: Node = structure_node.get_node_or_null("VisualHandler")
	if vh and vh.has_method("set_upgrade_progress"):
		vh.call("set_upgrade_progress", progress)


func _complete_upgrade_visuals(c_structure: C_Structure) -> void:
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return
	var vh: Node = structure_node.get_node_or_null("VisualHandler")
	if vh and vh.has_method("complete_upgrade_animation"):
		vh.call("complete_upgrade_animation")


func _find_power_user(c_structure: C_Structure) -> Node3D:
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return null
	var power_node: Node = structure_node.get_node_or_null("PowerNode")
	if power_node == null:
		return null
	return power_node.get_node_or_null("PowerUser") as Node3D


func _get_autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/" + autoload_name)
