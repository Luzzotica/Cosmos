extends Entity
class_name EnemyEntity
## ECS entity for enemies. Root is Entity; child is CharacterBody3D with meshes.

const EXPLOSION_DURATION: float = 0.5
const EXPLOSION_SCALE_END: float = 3.0


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
		if body.has_method("initialize_visuals"):
			body.initialize_visuals(self)
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health and not c_health.destroyed.is_connected(_on_health_destroyed):
		c_health.destroyed.connect(_on_health_destroyed)


func is_destroyed() -> bool:
	var c: C_EnemyState = get_component(C_EnemyState) as C_EnemyState
	return c != null and c.is_destroyed


func _find_physics_body() -> CharacterBody3D:
	var body: Node = get_node_or_null("ShipBody")
	if body is CharacterBody3D:
		return body as CharacterBody3D
	for child in get_children():
		if child is CharacterBody3D:
			return child as CharacterBody3D
	return null


func spawn_death_explosion_at_body() -> void:
	var body_ref: C_PhysicsBodyRef = get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var body: Node = body_ref.body if body_ref and body_ref.body else null
	if body and is_instance_valid(body):
		var c_t: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
		var pos: Vector3 = (body as Node3D).global_position if (body.is_inside_tree() and body is Node3D) else (c_t.position if c_t else Vector3.ZERO)
		_spawn_death_explosion(pos, _get_emission_color(body))


func _on_health_destroyed() -> void:
	add_component(C_Destroyed.new())
	var c_state: C_EnemyState = get_component(C_EnemyState) as C_EnemyState
	if c_state:
		c_state.is_destroyed = true
	var reward: int = int(c_state.reward_minerals) if c_state else 10
	GameState.add_minerals(reward)
	var body_ref: C_PhysicsBodyRef = get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var body: Node = body_ref.body if body_ref and body_ref.body else null
	var explosion_pos: Vector3 = Vector3.ZERO
	if body and is_instance_valid(body):
		if body.is_inside_tree() and body is Node3D:
			explosion_pos = (body as Node3D).global_position
		else:
			var c_transform: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
			explosion_pos = c_transform.position if c_transform else Vector3.ZERO
		_spawn_death_explosion(explosion_pos, _get_emission_color(body))
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager:
		if enemy_manager.has_method("clear_enemy_from_blackboard"):
			enemy_manager.clear_enemy_from_blackboard(body if body else self)
		if enemy_manager.has_method("_on_ecs_enemy_destroyed"):
			enemy_manager._on_ecs_enemy_destroyed(body if body else self)
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
	else:
		queue_free()


func _get_emission_color(body: Node) -> Color:
	var body_node: Node3D = body.get_node_or_null("Body") if body else null
	if body_node:
		for child in body_node.get_children():
			if child is MeshInstance3D:
				var mat: Material = (child as MeshInstance3D).get_active_material(0)
				if mat is ShaderMaterial:
					var col: Variant = (mat as ShaderMaterial).get_shader_parameter("emission_color")
					if col is Color:
						return col
					if col is Vector3:
						return Color(col.x, col.y, col.z, 1.0)
	return Color(1.0, 0.05, 0.2, 1.0)


func _spawn_death_explosion(pos: Vector3, emission_color: Color) -> void:
	var explosion_root: Node3D = Node3D.new()
	explosion_root.position = pos
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh.mesh = sphere
	var shader: Shader = load("res://shaders/enemy_energy_crackle.gdshader") as Shader
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("emission_color", Vector3(emission_color.r, emission_color.g, emission_color.b))
	mat.set_shader_parameter("emission_energy", 8.0)
	mat.set_shader_parameter("crackle_speed", 8.0)
	mat.set_shader_parameter("crackle_density", 16.0)
	mat.set_shader_parameter("crackle_sharpness", 6.0)
	mat.set_shader_parameter("core_brightness", 0.8)
	mat.set_shader_parameter("pulse_amount", 0.4)
	mat.set_shader_parameter("fresnel_power", 1.8)
	mesh.material_override = mat
	mesh.scale = Vector3(0.2, 0.2, 0.2)
	explosion_root.add_child(mesh)
	get_tree().root.add_child(explosion_root)
	var shrink_duration: float = 0.35
	var tween: Tween = explosion_root.create_tween()
	tween.tween_method(func(t: float) -> void:
		var s: float = lerpf(0.2, EXPLOSION_SCALE_END, t)
		mesh.scale = Vector3(s, s, s)
		mat.set_shader_parameter("emission_energy", lerpf(8.0, 2.0, t))
	, 0.0, 1.0, EXPLOSION_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float) -> void:
		var s: float = lerpf(EXPLOSION_SCALE_END, 0.05, t)
		mesh.scale = Vector3(s, s, s)
		mat.set_shader_parameter("emission_energy", lerpf(2.0, 0.0, t))
	, 0.0, 1.0, shrink_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(explosion_root.queue_free)
