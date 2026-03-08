extends Node
## Orients all solar panels toward the sun. Uses GameWorld.sun_light.
## Run every frame for built solar panels.

const E_SolarPanel: GDScript = preload("res://scripts/ecs/entities/e_solar_panel.gd")

func _process(_delta: float) -> void:
	var sun: DirectionalLight3D = GameWorld.sun_light if GameWorld else null
	if not sun or not is_instance_valid(sun):
		return

	var toward_sun: Vector3 = sun.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return

	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT

	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	var panel_basis: Basis = basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)

	var root: Node = get_tree().root
	_orient_solar_panels_in(root, panel_basis)


func _orient_solar_panels_in(node: Node, panel_basis: Basis) -> void:
	if (node is SolarPanel or node.get_script() == E_SolarPanel) and not node.is_destroyed:
		if node.is_built() and node.is_sun_tracking_active():
			var panel_mesh: MeshInstance3D = node.get_node_or_null("Panel") as MeshInstance3D
			if panel_mesh:
				panel_mesh.global_transform = Transform3D(panel_basis.orthonormalized(), panel_mesh.global_position)

	for child in node.get_children():
		_orient_solar_panels_in(child, panel_basis)
