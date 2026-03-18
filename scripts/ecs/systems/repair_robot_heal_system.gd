extends System
class_name RepairRobotHealSystem
## Fires heal beams and applies healing when robot is in range of target structure.

const BeamPointResolverClass = preload("res://scripts/ecs/beam_point_resolver.gd")
const C_RepairRobotStateClass = preload("res://scripts/ecs/components/c_repair_robot_state.gd")
const C_HealBeamClass = preload("res://scripts/ecs/components/c_heal_beam.gd")

var _beam_system: BeamWeaponSystem


func query() -> QueryBuilder:
	return q.with_all([C_RepairRobotStateClass, C_HealBeamClass, C_Targeting, C_PhysicsBodyRef])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	if _beam_system == null and ECS and ECS.world:
		for s in ECS.world.systems:
			if s is BeamWeaponSystem:
				_beam_system = s as BeamWeaponSystem
				break
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_state = entity.get_component(C_RepairRobotStateClass) as C_RepairRobotState
	var c_heal = entity.get_component(C_HealBeamClass) as C_HealBeam
	var _c_targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	if c_state == null or c_heal == null or c_body_ref == null or c_body_ref.body == null:
		return
	if c_state.state != C_RepairRobotState.State.HEALING:
		return
	if c_state.heals_remaining <= 0:
		return
	var target: Node3D = c_state.target_structure
	if target == null or not is_instance_valid(target):
		return

	var body: Node3D = c_body_ref.body
	var dist: float = body.global_position.distance_to(target.global_position)
	if dist > c_heal.heal_range:
		return

	c_heal.cooldown_remaining = maxf(c_heal.cooldown_remaining - delta, 0.0)
	if c_heal.cooldown_remaining > 0.0:
		return

	var from_pos: Vector3 = BeamPointResolverClass.get_beam_emit_point(body)
	var target_pos: Vector3 = BeamPointResolverClass.get_random_attack_point(target)
	if _beam_system:
		_beam_system.play_heal_beam(from_pos, target_pos)

	var heal_amount: float = c_heal.heal_rate * c_heal.attack_cooldown
	var c_health: C_Health = _get_health_from_target(target)
	if c_health:
		c_health.heal(heal_amount)

	c_state.heals_remaining = maxi(0, c_state.heals_remaining - 1)
	c_heal.cooldown_remaining = c_heal.attack_cooldown


func _get_health_from_target(target: Node) -> C_Health:
	var n: Node = target
	while n:
		if n.has_method("get_component"):
			var c: C_Health = n.get_component(C_Health) as C_Health
			if c:
				return c
		n = n.get_parent()
	return null
