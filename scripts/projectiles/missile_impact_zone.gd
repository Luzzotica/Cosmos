extends Node3D
class_name MissileImpactZone
## Short-lived Area3D that applies AoE damage to overlapping bodies, then frees.

@export var damage: float = 25.0
@export var damage_type: String = "physical"
@export var aoe_radius: float = 6.0

var _source: Node = null


func setup(p_damage: float, p_damage_type: String, p_aoe_radius: float, p_source: Node = null) -> void:
	damage = p_damage
	damage_type = p_damage_type
	aoe_radius = p_aoe_radius
	_source = p_source


func _ready() -> void:
	var area: Area3D = _find_area()
	if area:
		var shape_node: CollisionShape3D = area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is SphereShape3D:
			(shape_node.shape as SphereShape3D).radius = aoe_radius
	call_deferred("_apply_damage")


func _find_area() -> Area3D:
	for child in get_children():
		if child is Area3D:
			return child as Area3D
	return null


func _apply_damage() -> void:
	var area: Area3D = _find_area()
	if area == null:
		queue_free()
		return

	var packet: Dictionary = {
		"amount": damage,
		"damage_type": damage_type,
		"source": _source,
		"tags": PackedStringArray()
	}

	for body in area.get_overlapping_bodies():
		var target: Node = _find_damageable(body)
		if target and target.has_method("take_damage_event"):
			target.take_damage_event(packet)

	for overlapping_area in area.get_overlapping_areas():
		var target: Node = _find_damageable(overlapping_area)
		if target and target.has_method("take_damage_event"):
			target.take_damage_event(packet)

	queue_free()


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n:
		if n.has_method("take_damage_event"):
			return n
		n = n.get_parent()
	return null
