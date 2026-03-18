extends System
class_name BeamPointsSetupSystem
## One-time setup: finds BeamEmitPoint and AttackPoint markers in body subtree,
## populates C_BeamPoints for O(1) beam point lookup. Query excludes entities
## that already have C_BeamPoints.

const C_BeamPointsClass = preload("res://scripts/ecs/components/c_beam_points.gd")


func query() -> QueryBuilder:
	return q.with_any([C_PhysicsBodyRef, C_Structure]).with_none([C_Destroyed, C_BeamPointsClass])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		_setup_beam_points(entity)


func _setup_beam_points(entity: Entity) -> void:
	var body_node: Node3D = null
	var c_body: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_body and c_body.body and is_instance_valid(c_body.body):
		body_node = c_body.body
	elif c_structure and c_structure.structure_node and is_instance_valid(c_structure.structure_node):
		body_node = c_structure.structure_node
	if body_node == null:
		return

	var result: Dictionary = _collect_markers(body_node)

	var c_beam = C_BeamPointsClass.new()
	c_beam.emit_point = result.emit_point
	var typed_attack: Array[Node3D] = []
	for n in result.attack_points:
		typed_attack.append(n as Node3D)
	c_beam.attack_points = typed_attack
	entity.add_component(c_beam)


func _collect_markers(root: Node) -> Dictionary:
	var emit_ref: Array = [null]
	var attack_ref: Array = [[]]
	_collect_markers_impl(root, emit_ref, attack_ref)
	return {"emit_point": emit_ref[0], "attack_points": attack_ref[0]}


func _collect_markers_impl(node: Node, emit_ref: Array, attack_ref: Array) -> void:
	if node is Marker3D:
		var marker_name: String = node.name
		if marker_name == "BeamEmitPoint":
			if emit_ref[0] == null:
				emit_ref[0] = node as Node3D
		elif marker_name == "AttackPoint":
			attack_ref[0].append(node as Node3D)
	for child in node.get_children():
		_collect_markers_impl(child, emit_ref, attack_ref)
