extends System
class_name MinimapSystem
## Populates MinimapData via ECS queries. Fast archetype-based lookups for structures and enemies.


func _init() -> void:
	process_empty = true


func query() -> QueryBuilder:
	## Dummy query - we run our own queries in process. process_empty ensures we always run.
	return q.with_all([C_Structure])


func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	if not MinimapData:
		return

	MinimapData.structure_positions.clear()
	MinimapData.enemy_positions.clear()
	MinimapData.asteroid_positions.clear()

	_collect_structures()
	_collect_enemies()
	_collect_asteroids()


func _collect_structures() -> void:
	if not ECS or not ECS.world:
		return
	var entities: Array = ECS.world.query.with_all([C_Structure, C_Team]).execute()
	for entity in entities:
		var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
		if not c_structure or c_structure.is_destroyed:
			continue
		var c_team: C_Team = entity.get_component(C_Team) as C_Team
		if c_team and c_team.team != "player":
			continue
		var pos: Vector3
		if c_structure.structure_node and is_instance_valid(c_structure.structure_node):
			pos = c_structure.structure_node.global_position
		else:
			var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
			if c_transform:
				pos = c_transform.position
			else:
				continue
		MinimapData.structure_positions.append(pos)


func _collect_enemies() -> void:
	if not ECS or not ECS.world:
		return
	var entities: Array = ECS.world.query.with_all([C_EnemyState, C_Transform3D, C_Team]).execute()
	for entity in entities:
		var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
		if not c_state or c_state.is_destroyed:
			continue
		var c_team: C_Team = entity.get_component(C_Team) as C_Team
		if c_team and c_team.team != "enemy":
			continue
		var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
		if not c_transform:
			continue
		var pos: Vector3 = c_transform.position
		var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
		if body_ref and body_ref.body and is_instance_valid(body_ref.body):
			pos = body_ref.body.global_position
		MinimapData.enemy_positions.append(pos)


func _collect_asteroids() -> void:
	var main: Node = Engine.get_main_loop().root.get_node_or_null("Main")
	if not main:
		return
	var asteroids_parent: Node = main.get_node_or_null("Asteroids")
	if not asteroids_parent:
		return
	for child in asteroids_parent.get_children():
		if child is Node3D and is_instance_valid(child):
			MinimapData.asteroid_positions.append((child as Node3D).global_position)
