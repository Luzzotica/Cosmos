extends System
class_name StructureTargetingSystem
## Populates C_Targeting.target_node for structure beam weapons and missile turrets.
## Uses ECS query for enemies (team=enemy, C_EnemyState, C_PhysicsBodyRef).

const C_MissileLauncherClass = preload("res://scripts/ecs/components/c_missile_launcher.gd")
const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")

func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_Targeting]).with_any([C_BeamWeapon, C_MissileLauncherClass]).with_none([C_Construction])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, _delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_weapon: C_BeamWeapon = entity.get_component(C_BeamWeapon) as C_BeamWeapon
	var c_launcher = entity.get_component(C_MissileLauncherClass)
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	if c_structure == null or c_targeting == null or c_structure.is_destroyed:
		return
	if c_weapon == null and c_launcher == null:
		return
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_upgrades and c_upgrades.is_upgrading:
		return
	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return
	var attack_range: float = c_weapon.attack_range if c_weapon else c_launcher.attack_range
	if c_targeting.target_node != null:
		if not is_instance_valid(c_targeting.target_node):
			c_targeting.target_node = null
		elif _is_target_destroyed(c_targeting.target_node):
			c_targeting.target_node = null
		elif structure_node.global_position.distance_to(c_targeting.target_node.global_position) > attack_range:
			c_targeting.target_node = null
	if c_targeting.target_node == null:
		c_targeting.target_node = _find_closest_enemy(structure_node, attack_range)


func _find_closest_enemy(from: Node3D, attack_range: float) -> Node3D:
	if ECS == null or ECS.world == null:
		return null
	var enemies: Array = ECS.world.query.with_all([
		{C_EnemyState: {"is_destroyed": {"_eq": false}}},
		{C_Team: {"team": {"_eq": "enemy"}}},
		C_PhysicsBodyRef
	]).execute()
	var closest_distance: float = INF
	var closest_enemy: Node3D = null
	for entity in enemies:
		var c_body: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_body == null or c_body.body == null or not is_instance_valid(c_body.body):
			continue
		var distance: float = from.global_position.distance_to(c_body.body.global_position)
		if distance <= attack_range and distance < closest_distance:
			closest_distance = distance
			closest_enemy = c_body.body
	return closest_enemy


func _is_target_destroyed(t: Node) -> bool:
	var n: Node = t
	while n:
		if n is Entity:
			var c_state: C_EnemyState = n.get_component(C_EnemyState) as C_EnemyState
			return c_state != null and c_state.is_destroyed
		n = n.get_parent()
	return false
