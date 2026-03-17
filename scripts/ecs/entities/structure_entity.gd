extends Entity
class_name StructureEntity
## ECS entity for player structures. Root is Entity; child is Node3D body with meshes, power, visuals.
## Mirrors EnemyEntity pattern: entity owns components, body is thin proxy for damage/selection.

const C_DestroyedClass = preload("res://scripts/ecs/components/c_destroyed.gd")

signal destroyed


func define_components() -> Array:
	return []


func on_ready() -> void:
	var body: Node3D = _find_structure_body()
	if body:
		var c_structure: C_Structure = get_component(C_Structure) as C_Structure
		if c_structure:
			c_structure.structure_node = body
		var c_transform: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
		if c_transform:
			c_transform.position = body.global_position
			c_transform.rotation = body.rotation
		if body.has_method("initialize_visuals"):
			body.initialize_visuals(self)
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health and not c_health.destroyed.is_connected(_on_health_destroyed):
		c_health.destroyed.connect(_on_health_destroyed)


func is_destroyed() -> bool:
	var c: C_Structure = get_component(C_Structure) as C_Structure
	return c != null and c.is_destroyed


func set_starter_panel(is_starter: bool) -> void:
	var body: Node3D = _find_structure_body()
	if body and body.has_method("set_starter_panel"):
		body.call("set_starter_panel", is_starter)


func _find_structure_body() -> Node3D:
	var body: Node = get_node_or_null("StructureBody")
	if body is Node3D:
		return body as Node3D
	for child in get_children():
		if child is Node3D:
			return child as Node3D
	return null


func _on_health_destroyed() -> void:
	add_component(C_DestroyedClass.new())
	var c_structure: C_Structure = get_component(C_Structure) as C_Structure
	if c_structure:
		c_structure.is_destroyed = true
	destroyed.emit()
	var body: Node3D = _find_structure_body()
	if body and is_instance_valid(body):
		var render_manager: Node = get_tree().root.get_node_or_null("StructureRenderManager")
		if render_manager and render_manager.has_method("unregister_structure"):
			render_manager.unregister_structure(body)
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
	else:
		queue_free()
