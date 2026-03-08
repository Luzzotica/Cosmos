extends System
class_name LaserTurretAttackSystem
## Batch attack: cooldown, power check, damage application, triggers structure visuals.

func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_TurretProfile, C_Targeting, C_PowerUser])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_attack(entity, delta)


func _process_entity_attack(entity: Entity, delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_turret: C_TurretProfile = entity.get_component(C_TurretProfile) as C_TurretProfile
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	if c_structure == null or c_turret == null or c_targeting == null:
		return
	if c_structure.building_type != "laser_turret":
		return
	if c_structure.is_destroyed:
		return
	var structure: Node3D = c_structure.structure_node as Node3D
	if structure == null or not is_instance_valid(structure):
		return
	if not structure.has_method("is_built") or not structure.is_built():
		return
	var c_power_user: C_PowerUser = entity.get_component(C_PowerUser) as C_PowerUser
	if c_power_user == null:
		return
	# Draw power on demand before checking
	var _drawn: float = PowerGraph.draw_power_for_user_entity(entity, c_power_user.use_power_cost)
	if not c_power_user.has_power():
		return

	var target: Node3D = c_targeting.target_node
	if target == null or not is_instance_valid(target):
		return

	# Update cooldown
	c_turret.fire_timer = maxf(c_turret.fire_timer - delta, 0.0)
	if c_turret.fire_timer > 0.0:
		return

	# Range check
	if structure.global_position.distance_to(target.global_position) > c_turret.attack_range:
		return

	# Consume power (already drew above)
	if c_power_user.power_buffer < c_power_user.use_power_cost:
		return
	c_power_user.power_buffer -= c_power_user.use_power_cost
	c_power_user.power_consumption = c_power_user.use_power_cost

	# Fire!
	c_turret.fire_timer = 1.0 / c_turret.fire_rate
	var target_pos: Vector3 = target.global_position + Vector3.UP * 0.8

	# Damage target
	if target.has_method("take_damage_event"):
		target.take_damage_event({
			"amount": c_turret.damage,
			"damage_type": "laser",
			"source": structure,
			"tags": PackedStringArray()
		})
	elif target.has_method("take_damage"):
		target.take_damage(c_turret.damage)

	# Visuals (beam, orb flash, SFX) - delegate to structure
	if structure.has_method("play_attack_visuals"):
		structure.play_attack_visuals(target_pos, c_turret.beam_color)

	if structure.has_signal("fired"):
		structure.fired.emit(target, c_turret.damage)
