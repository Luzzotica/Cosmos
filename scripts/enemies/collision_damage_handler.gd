extends RefCounted
class_name EnemyCollisionDamageHandler
## Handles collision/overlap damage when fighters kamikaze into structures or asteroids.
## Call after move_and_slide() to process overlaps and apply damage both ways.

## Minimum speed to trigger impact damage (avoids grazing taps)
const MIN_IMPACT_SPEED: float = 1.5
## Base collision damage from impact (scaled by speed)
const BASE_IMPACT_DAMAGE: float = 15.0
## Damage multiplier based on impact speed
const SPEED_DAMAGE_SCALE: float = 2.0
## Minerals removed from asteroid per point of impact damage
const ASTEROID_MINERAL_DAMAGE_RATIO: float = 2.0
## Collision layer for selectables (structures, asteroids)
const SELECTABLE_LAYER: int = 1 << 1


## Process overlap collisions after move_and_slide. Applies damage to both enemy and collided objects.
## Returns true if enemy was destroyed by impact.
static func process_collision_damage(enemy: CharacterBody3D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false

	var overlap_colliders: Array = _get_overlapping_colliders(enemy)
	if overlap_colliders.is_empty():
		return false

	var impact_speed: float = Vector3(enemy.velocity.x, 0.0, enemy.velocity.z).length()
	if impact_speed < MIN_IMPACT_SPEED:
		return false

	var damage_to_deal: float = BASE_IMPACT_DAMAGE + impact_speed * SPEED_DAMAGE_SCALE
	var damage_to_self: float = damage_to_deal * 0.5  # Enemy takes half

	for collider in overlap_colliders:
		_apply_damage_to_collider(collider, damage_to_deal, enemy)

	if enemy.has_method("take_damage_event"):
		enemy.take_damage_event({
			"amount": damage_to_self,
			"damage_type": "physical",
			"source": null,
			"tags": PackedStringArray(["impact"])
		})
		return _get_enemy_health(enemy) <= 0
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage_to_self)
		return _get_enemy_health(enemy) <= 0

	return false


static func _get_overlapping_colliders(enemy: CharacterBody3D) -> Array:
	var space_state: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	if space_state == null:
		return []

	var shape: Shape3D = null
	for child in enemy.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs.shape != null:
				shape = cs.shape
				break
	if shape == null:
		return []

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = enemy.global_transform
	query.collision_mask = SELECTABLE_LAYER
	query.collide_with_bodies = false
	query.collide_with_areas = true
	query.exclude = [enemy]

	var results: Array = space_state.intersect_shape(query, 16)
	var colliders: Array = []
	var seen: Dictionary = {}

	for hit in results:
		var collider: Object = hit.get("collider", null)
		if collider == null or seen.has(collider.get_instance_id()):
			continue
		var owner_node: Node = _get_owner_entity(collider)
		if owner_node != null and _is_valid_impact_target(owner_node, enemy):
			seen[collider.get_instance_id()] = true
			colliders.append(owner_node)

	return colliders


static func _get_owner_entity(collider: Object) -> Node:
	if collider is Node:
		var node: Node = collider as Node
		# SelectableComponent (Area3D) - owner is the parent structure/asteroid
		if node.get_parent() != null:
			return node.get_parent()
		return node
	return null


static func _is_valid_impact_target(node: Node, _enemy: CharacterBody3D) -> bool:
	# Don't collide with other enemies
	if node is CharacterBody3D and node.get("enemy_id") != null:
		return false
	# Structures (BaseStructure or Entity-based)
	if node is BaseStructure:
		return not node.is_destroyed
	if node.get("building_type") != null and node.has_method("is_built"):
		return not node.get("is_destroyed")
	if node.get("is_destroyed") == true:
		return false
	# Asteroid (has mine_minerals and remaining_minerals)
	if node.has_method("mine_minerals") and node.get("remaining_minerals") != null:
		return not node.is_depleted
	# Can take damage
	if node.has_method("take_damage_event") or node.has_method("take_damage"):
		return true
	return false


static func _apply_damage_to_collider(owner_node: Node, damage: float, source: Node3D) -> void:
	if owner_node.has_method("mine_minerals") and owner_node.get("remaining_minerals") != null:
		var mineral_loss: int = mini(int(damage * ASTEROID_MINERAL_DAMAGE_RATIO), int(owner_node.remaining_minerals))
		if mineral_loss > 0:
			owner_node.mine_minerals(mineral_loss)
			if owner_node.has_method("show_mining_impact"):
				owner_node.show_mining_impact()
		return

	var packet: Dictionary = {
		"amount": damage,
		"damage_type": "physical",
		"source": source,
		"tags": PackedStringArray(["impact"])
	}
	if owner_node.has_method("take_damage_event"):
		owner_node.take_damage_event(packet)
	elif owner_node.has_method("take_damage"):
		owner_node.take_damage(damage)


static func _get_enemy_health(enemy: CharacterBody3D) -> float:
	var entity: Node = enemy.get_parent()
	if entity and entity.has_method("get_component"):
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		if c_health:
			return c_health.current
	return 0.0
