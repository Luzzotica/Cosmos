extends Node3D
class_name EnemyDeathEffect
## One-shot energy crackle explosion when an enemy dies. Expands and fades.

const CRACKLE_SHADER: Shader = preload("res://shaders/enemy_energy_crackle.gdshader")
const DURATION: float = 0.35


static func spawn_at(pos: Vector3, emission_color: Color = Color(1.0, 0.1, 0.2)) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "EnemyDeathEffect"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	mesh_inst.mesh = sphere

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = CRACKLE_SHADER
	mat.set_shader_parameter("emission_color", Vector3(emission_color.r, emission_color.g, emission_color.b))
	mat.set_shader_parameter("emission_energy", 4.0)
	mat.set_shader_parameter("crackle_speed", 12.0)
	mat.set_shader_parameter("crackle_density", 40.0)
	mat.set_shader_parameter("core_brightness", 0.9)
	mat.set_shader_parameter("pulse_amount", 0.4)
	mesh_inst.material_override = mat

	tree.root.add_child(mesh_inst)
	mesh_inst.global_position = pos

	var tween: Tween = tree.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_inst, "scale", Vector3(2.5, 2.5, 2.5), DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(mat, "shader_parameter/emission_energy", 0.0, DURATION).set_delay(DURATION * 0.3)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	)
