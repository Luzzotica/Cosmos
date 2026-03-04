extends Entity
class_name EnemyEntity
## ECS entity for enemies. Root is Entity; child is CharacterBody3D with meshes and legacy components.


func define_components() -> Array:
	return []


func on_ready() -> void:
	var body: CharacterBody3D = _find_physics_body()
	if body:
		var c_ref: C_PhysicsBodyRef = get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_ref:
			c_ref.body = body
		var c_transform: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
		if c_transform:
			c_transform.position = body.global_position
			c_transform.rotation = body.rotation
		var c_targeting: C_Targeting = get_component(C_Targeting) as C_Targeting
		if c_targeting:
			c_targeting.fallback_position = body.global_position + Vector3.FORWARD * 8.0
			c_targeting.forward_direction = -body.global_basis.z
		# Connect legacy HealthComponent.destroyed to ECS cleanup
		for child in body.get_children():
			if child is HealthComponent:
				if not child.destroyed.is_connected(_on_legacy_health_destroyed):
					child.destroyed.connect(_on_legacy_health_destroyed)
				break


func _find_physics_body() -> CharacterBody3D:
	for child in get_children():
		if child is CharacterBody3D:
			return child as CharacterBody3D
	return null


func _on_legacy_health_destroyed() -> void:
	var c_state: C_EnemyState = get_component(C_EnemyState) as C_EnemyState
	if c_state:
		c_state.is_destroyed = true
	var reward: int = int(c_state.reward_minerals) if c_state else 10
	GameState.add_minerals(reward)
	var body_ref: C_PhysicsBodyRef = get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var body: Node = body_ref.body if body_ref and body_ref.body else self
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager:
		if enemy_manager.has_method("clear_enemy_from_blackboard"):
			enemy_manager.clear_enemy_from_blackboard(body)
		if enemy_manager.has_method("_on_ecs_enemy_destroyed"):
			enemy_manager._on_ecs_enemy_destroyed(body)
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
	else:
		queue_free()
