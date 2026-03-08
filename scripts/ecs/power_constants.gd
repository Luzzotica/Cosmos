class_name PowerConstants
extends RefCounted
## Shared constants and utilities for power grid (used by ECS and BuildManager).
## Replaces PowerNode.CONNECTION_RANGE and has_line_of_sight.

## Connection range - controls both visual indicator AND actual connections
const CONNECTION_RANGE: float = 15.0


## Check if there's a clear line of sight between two positions.
## Excludes the two endpoint structures from the raycast.
static func has_line_of_sight(from_pos: Vector3, to_pos: Vector3, exclude1: Node3D = null, exclude2: Node3D = null) -> bool:
	var world: World3D = exclude1.get_world_3d() if exclude1 else null
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state if world else null
	if not space_state:
		return true  # Can't check (headless, not in tree), assume clear

	# Raise the check slightly above ground
	var start: Vector3 = from_pos + Vector3(0, 0.5, 0)
	var end: Vector3 = to_pos + Vector3(0, 0.5, 0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 0xFFFFFFFF  # Check all layers
	query.collide_with_bodies = true
	query.collide_with_areas = true

	# Exclude the two structures we're connecting
	var exclude_rids: Array[RID] = []
	if exclude1:
		var body1: CollisionObject3D = _find_collision_body(exclude1)
		if body1:
			exclude_rids.append(body1.get_rid())
	if exclude2:
		var body2: CollisionObject3D = _find_collision_body(exclude2)
		if body2:
			exclude_rids.append(body2.get_rid())
	query.exclude = exclude_rids

	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()  # Clear if nothing hit


## Find collision body in a node hierarchy
static func _find_collision_body(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var body: CollisionObject3D = _find_collision_body(child)
		if body:
			return body
	return null
