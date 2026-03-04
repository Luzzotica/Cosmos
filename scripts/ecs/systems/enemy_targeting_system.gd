extends System
class_name EnemyTargetingSystem
## Batch targeting: fetches player structures once per frame, assigns targets to enemies.

const MovementBehaviorClass: Script = preload("res://scripts/enemies/behaviors/movement_behavior.gd")
const TargetingBehaviorClass: Script = preload("res://scripts/enemies/behaviors/targeting_behavior.gd")

var _movement_behavior: RefCounted
var _targeting_behavior: RefCounted
var _player_structures_cache: Array[Node3D] = []
var _cache_valid: bool = false


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D]).with_none([])


func setup() -> void:
	_movement_behavior = MovementBehaviorClass.new()
	_targeting_behavior = TargetingBehaviorClass.new()


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	if entities.is_empty():
		return
	# Batch-fetch player structures once per frame
	_refresh_structures_cache()
	for entity in entities:
		_process_entity_targeting(entity, delta)


func _refresh_structures_cache() -> void:
	_player_structures_cache.clear()
	# Prefer ECS query for player structures when available
	if ECS and ECS.world:
		var structure_entities = ECS.world.query.with_all([C_Structure, C_Team]).execute()
		for entity in structure_entities:
			var c_team: C_Team = entity.get_component(C_Team) as C_Team
			if c_team and c_team.team != "player":
				continue
			var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
			if c_structure and c_structure.structure_node and is_instance_valid(c_structure.structure_node) and not c_structure.is_destroyed:
				_player_structures_cache.append(c_structure.structure_node)
		if not _player_structures_cache.is_empty():
			return
	# Fallback: scene tree
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
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var retarget_interval: float = _targeting_behavior.get_retarget_interval(tactical) if _targeting_behavior else 0.5
	c_targeting.retarget_timer -= delta
	var should_retarget: bool = c_targeting.retarget_timer <= 0.0
	if should_retarget:
		c_targeting.retarget_timer = retarget_interval
	# Validate current target
	if c_targeting.target_node != null:
		if not is_instance_valid(c_targeting.target_node) or c_targeting.target_node.get("is_destroyed") == true:
			c_targeting.target_node = null
	if should_retarget and not _should_hold_target(c_state, c_targeting):
		var candidates: Array = _player_structures_cache.duplicate()
		var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		var node_for_choose: Node3D = body_ref.body if body_ref and body_ref.body else null
		if node_for_choose and _targeting_behavior:
			c_targeting.target_node = _targeting_behavior.choose_target(node_for_choose, candidates, tactical)
		else:
			c_targeting.target_node = null


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
