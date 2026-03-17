extends System
class_name StructureTargetingSystem
## Populates C_Targeting.target_node for structure beam weapons (e.g. laser turrets).
## Scans Main/Enemies for closest valid enemy within attack range.

const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")

func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_BeamWeapon, C_Targeting]).with_none([C_Construction])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, _delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_weapon: C_BeamWeapon = entity.get_component(C_BeamWeapon) as C_BeamWeapon
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	if c_structure == null or c_weapon == null or c_targeting == null or c_structure.is_destroyed:
		return
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades and c_upgrades.is_upgrading:
		return
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return
	if c_targeting.target_node != null:
		if not is_instance_valid(c_targeting.target_node):
			c_targeting.target_node = null
		elif _is_target_destroyed(c_targeting.target_node):
			c_targeting.target_node = null
		elif structure_node.global_position.distance_to(c_targeting.target_node.global_position) > c_weapon.attack_range:
			c_targeting.target_node = null
	if c_targeting.target_node == null:
		c_targeting.target_node = _find_closest_enemy(structure_node, c_weapon.attack_range)


func _find_closest_enemy(from: Node3D, attack_range: float) -> Node3D:
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return null
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if not enemies_parent:
		return null
	var closest_distance: float = INF
	var closest_enemy: Node3D = null
	for child in enemies_parent.get_children():
		var spatial: Node3D = _get_enemy_spatial(child)
		var logical: Node = child
		if spatial == null or _is_target_destroyed(logical):
			continue
		var distance: float = from.global_position.distance_to(spatial.global_position)
		if distance <= attack_range and distance < closest_distance:
			closest_distance = distance
			closest_enemy = spatial
	return closest_enemy


func _get_enemy_spatial(node: Node) -> Node3D:
	if node is Node3D:
		return node as Node3D
	for c in node.get_children():
		if c is CharacterBody3D:
			return c as CharacterBody3D
	return null


func _is_target_destroyed(t: Node) -> bool:
	if t.has_method("is_destroyed"):
		return t.call("is_destroyed")
	if t.get("is_destroyed") != null:
		return t.get("is_destroyed")
	return false
