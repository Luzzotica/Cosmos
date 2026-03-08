extends System
class_name EnemyDestructionSystem
## When C_Health.current <= 0 for entities with C_PhysicsBodyRef (enemies), run death logic and remove.

func query() -> QueryBuilder:
	return q.with_all([C_Health, C_PhysicsBodyRef]).with_none([C_Structure])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		var c_body: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if c_health == null or c_body == null:
			continue
		if c_health.current > 0:
			continue

		var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
		if c_state:
			c_state.is_destroyed = true

		var body: Node = c_body.body
		var reward: int = int(c_state.reward_minerals) if c_state else 10

		var emit_color: Color = Color(1.0, 0.1, 0.2)
		if body and body.get("enemy_data") != null:
			var data: Resource = body.get("enemy_data")
			if data and data.get("emission_color") != null:
				emit_color = data.emission_color

		var pos: Vector3 = body.global_position if body and is_instance_valid(body) else Vector3.ZERO
		EnemyDeathEffect.spawn_at(pos, emit_color)
		_play_death_sfx()
		GameState.add_minerals(reward)

		var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
		if enemy_manager:
			if enemy_manager.has_method("clear_enemy_from_blackboard"):
				enemy_manager.clear_enemy_from_blackboard(body)
			if enemy_manager.has_method("_on_ecs_enemy_destroyed"):
				enemy_manager._on_ecs_enemy_destroyed(body)

		if ECS and ECS.world:
			ECS.world.remove_entity(entity)
		if entity is Node:
			entity.queue_free()


func _play_death_sfx() -> void:
	var sfx: Node = Engine.get_main_loop().root.get_node_or_null("SfxManager")
	if sfx and sfx.has_method("play_sfx"):
		sfx.call("play_sfx", "enemy_death", -6.0)
