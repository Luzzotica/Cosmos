extends System
class_name EnemyAbilitySystem
## Processes special abilities (sabotage, commander aura) for entities with ability_profile.

const EnemyAbilityBehaviorClass: Script = preload("res://scripts/enemies/behaviors/ability_behavior.gd")

var _behaviors: Dictionary = {}  # entity instance id -> EnemyAbilityBehavior


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_PhysicsBodyRef, C_AttackProfile])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_attack: C_AttackProfile = entity.get_component(C_AttackProfile) as C_AttackProfile
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
		return
	var ability_profile: Dictionary = c_attack.ability_profile if c_attack else {}
	if ability_profile.is_empty() or not ability_profile.has("type"):
		return

	var behavior: RefCounted = _get_or_create_behavior(entity, c_attack)
	var target: Node3D = null
	if c_targeting and c_targeting.target_node != null:
		var raw: Variant = c_targeting.target_node
		if raw != null and is_instance_valid(raw):
			target = raw as Node3D
	var body: CharacterBody3D = c_body_ref.body
	behavior.tick(delta, body, target)


func _get_or_create_behavior(entity: Entity, c_attack: C_AttackProfile) -> RefCounted:
	var id_key: int = entity.get_instance_id()
	if _behaviors.has(id_key):
		return _behaviors[id_key]
	var behavior: RefCounted = EnemyAbilityBehaviorClass.new()
	behavior.configure(c_attack.ability_profile)
	_behaviors[id_key] = behavior
	return behavior
