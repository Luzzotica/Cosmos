extends Entity
class_name EnemyEntity
## ECS entity for enemies. Root is Entity; child is CharacterBody3D with meshes and SelectableComponent.

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


func _find_physics_body() -> CharacterBody3D:
	for child in get_children():
		if child is CharacterBody3D:
			return child as CharacterBody3D
	return null
