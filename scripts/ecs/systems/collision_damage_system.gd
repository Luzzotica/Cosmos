extends System
class_name CollisionDamageSystem
## Handles collision damage: applies damage to structures/asteroids on impact, destroys fighter.


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_PhysicsBodyRef, C_CollisionDamage])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_collisions(entity)


func _process_entity_collisions(entity: Entity) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_collision: C_CollisionDamage = entity.get_component(C_CollisionDamage) as C_CollisionDamage
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null or c_collision == null:
		return
	var body: CharacterBody3D = c_body_ref.body

	var slide_count: int = body.get_slide_collision_count()
	if slide_count <= 0:
		return

	var hit_non_enemy: bool = false
	for i in range(slide_count):
		var collision: KinematicCollision3D = body.get_slide_collision(i)
		if collision == null:
			continue
		var collider: Object = collision.get_collider()
		if collider == null or collider == body:
			continue
		if _is_enemy_body(collider):
			continue
		hit_non_enemy = true
		var damage_target: Node = _resolve_damage_target(collider)
		if damage_target == null:
			continue
		var packet: Dictionary = {
			"amount": c_collision.amount,
			"damage_type": "physical",
			"source": body,
			"tags": PackedStringArray()
		}
		if damage_target.has_method("take_damage_event"):
			damage_target.take_damage_event(packet)
		elif damage_target.has_method("take_damage"):
			damage_target.take_damage(float(packet.amount))

	if c_collision.destroy_on_collision and hit_non_enemy:
		_destroy_fighter(entity, c_state, body)


func _is_enemy_body(collider: Object) -> bool:
	var node: Node = collider as Node
	if node == null:
		return false
	return node is EnemyShipBase


func _resolve_damage_target(collider: Object) -> Node:
	var node: Node = collider as Node
	if node == null:
		return null
	while node:
		if node.has_method("take_damage_event") or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null


func _destroy_fighter(entity: Entity, c_state: C_EnemyState, body: Node) -> void:
	if entity.has_method("spawn_death_explosion_at_body"):
		entity.spawn_death_explosion_at_body()
	entity.add_component(C_Destroyed.new())
	c_state.is_destroyed = true
	var reward: int = int(c_state.reward_minerals) if c_state else 10
	GameState.add_minerals(reward)
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager:
		if enemy_manager.has_method("clear_enemy_from_blackboard"):
			enemy_manager.clear_enemy_from_blackboard(body)
		if enemy_manager.has_method("_on_ecs_enemy_destroyed"):
			enemy_manager._on_ecs_enemy_destroyed(body)
	if ECS and ECS.world:
		ECS.world.remove_entity(entity)
	elif entity is Node:
		(entity as Node).queue_free()
