extends System
class_name EnemyTargetingSystem
## Batch targeting: fetches player structures once per frame, assigns targets to enemies.

const TargetingBehaviorClass: Script = preload("res://scripts/enemies/behaviors/targeting_behavior.gd")
const C_RepairRobotStateClass = preload("res://scripts/ecs/components/c_repair_robot_state.gd")

var _targeting_behavior: RefCounted
var _player_structures_cache: Array[Node3D] = []


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D]).with_none([])


func setup() -> void:
	_targeting_behavior = TargetingBehaviorClass.new()


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	if entities.is_empty():
		return
	_refresh_structures_cache()
	for entity in entities:
		_process_entity_targeting(entity, delta)


func _refresh_structures_cache() -> void:
	_player_structures_cache.clear()
	if ECS and ECS.world:
		var structure_entities = ECS.world.query.with_all([C_Structure, C_Team]).execute()
		for entity in structure_entities:
			var c_team: C_Team = entity.get_component(C_Team) as C_Team
			if c_team and c_team.team != "player":
				continue
			var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
			if c_structure and c_structure.structure_node and is_instance_valid(c_structure.structure_node) and not c_structure.is_destroyed:
				_player_structures_cache.append(c_structure.structure_node)
		# Add repair robots so enemies can target them
		var robot_entities = ECS.world.query.with_all([C_RepairRobotStateClass, C_PhysicsBodyRef, C_Health]).execute()
		for entity in robot_entities:
			var c_health: C_Health = entity.get_component(C_Health) as C_Health
			if c_health and c_health.is_destroyed:
				continue
			var c_body: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
			if c_body and c_body.body and is_instance_valid(c_body.body):
				_player_structures_cache.append(c_body.body)
		if not _player_structures_cache.is_empty():
			return
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return
	var structures_parent: Node = main.get_node_or_null("Structures")
	if not structures_parent:
		return
	for child in structures_parent.get_children():
		if child is BaseStructure and not child.is_destroyed:
			_player_structures_cache.append(child as Node3D)


func _process_entity_targeting(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	if c_state == null or c_targeting == null or c_transform == null or c_state.is_destroyed:
		return
	var c_tprofile: C_TargetingProfile = entity.get_component(C_TargetingProfile) as C_TargetingProfile
	if c_tprofile:
		_targeting_behavior.configure({"mode": c_tprofile.mode, "power_priority_bias": c_tprofile.power_priority_bias})
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var retarget_interval: float = c_tprofile.retarget_interval if c_tprofile else 0.5
	if tactical.has("retarget_interval_override"):
		retarget_interval = minf(retarget_interval, float(tactical["retarget_interval_override"]))
	c_targeting.retarget_timer -= delta
	var should_retarget: bool = c_targeting.retarget_timer <= 0.0
	if should_retarget:
		c_targeting.retarget_timer = retarget_interval
	if c_targeting.target_node != null:
		if not is_instance_valid(c_targeting.target_node) or c_targeting.target_node.get("is_destroyed") == true:
			c_targeting.target_node = null
	if should_retarget and not _should_hold_target(c_state, c_targeting):
		var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		var node_for_choose: Node3D = body_ref.body if body_ref and body_ref.body else null
		if c_state.enemy_id == "enemy_saboteur":
			_process_saboteur_targeting(entity, c_state, c_targeting, node_for_choose)
		elif node_for_choose and _targeting_behavior:
			var candidates: Array = _player_structures_cache.duplicate()
			c_targeting.target_node = _targeting_behavior.choose_target(node_for_choose, candidates, tactical)
			c_targeting.target_position = Vector3.INF
		else:
			c_targeting.target_node = null
			c_targeting.target_position = Vector3.INF


func _process_saboteur_targeting(entity: Entity, c_state: C_EnemyState, c_targeting: C_Targeting, node_for_choose: Node3D) -> void:
	var c_saboteur: C_SaboteurState = entity.get_component(C_SaboteurState) as C_SaboteurState
	if c_saboteur == null:
		c_targeting.target_node = null
		c_targeting.target_position = Vector3.INF
		return
	if c_saboteur.state != C_SaboteurState.State.MOVE_TO and c_saboteur.target_structure != null and is_instance_valid(c_saboteur.target_structure):
		return
	if node_for_choose == null or not _targeting_behavior:
		c_targeting.target_node = null
		c_targeting.target_position = Vector3.INF
		c_saboteur.target_structure = null
		c_saboteur.hover_position = Vector3.ZERO
		c_saboteur.target_line_start = Vector3.ZERO
		c_saboteur.target_line_end = Vector3.ZERO
		return
	var player_structures: Array = []
	for s in _player_structures_cache:
		player_structures.append(s)
	var result: Dictionary = _targeting_behavior.choose_saboteur_target(node_for_choose, player_structures)
	if result.is_empty():
		c_targeting.target_node = null
		c_targeting.target_position = Vector3.INF
		c_saboteur.target_structure = null
		c_saboteur.hover_position = Vector3.ZERO
		c_saboteur.target_line_start = Vector3.ZERO
		c_saboteur.target_line_end = Vector3.ZERO
		return
	c_targeting.target_node = result.target_structure
	c_targeting.target_position = result.hover_position
	c_saboteur.target_structure = result.target_structure
	c_saboteur.hover_position = result.hover_position
	c_saboteur.target_line_start = result.get("line_start", Vector3.ZERO)
	c_saboteur.target_line_end = result.get("line_end", Vector3.ZERO)


func _should_hold_target(c_state: C_EnemyState, c_targeting: C_Targeting) -> bool:
	if c_targeting.target_node == null or not is_instance_valid(c_targeting.target_node):
		return false
	if c_targeting.target_node.get("is_destroyed") == true:
		return false
	return false


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node = entity if body_ref == null or body_ref.body == null else body_ref.body
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)
