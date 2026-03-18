extends "res://scripts/structures/structure_visual_handler.gd"
class_name MissileTurretVisualHandler
## Missile turret visuals: uses barrel slots from scene, adds holders (missiles), missiles animate into position.

const C_MissileLauncherClass = preload("res://scripts/ecs/components/c_missile_launcher.gd")

const HOLDER_CYL_RADIUS: float = 0.08
const HOLDER_CYL_HEIGHT: float = 0.25
const ANIMATE_IN_DURATION: float = 0.4

@onready var _body: Node3D = get_parent() as Node3D
@onready var _holder_ring: Node3D = _body.get_node_or_null("VisualRoot/MissileRack/HolderRing") as Node3D

var _rack_slots: Array[Dictionary] = []
var _last_capacity: int = -1


func _get_register_structure_props() -> Dictionary:
	return {}


func init(entity: Node) -> void:
	super.init(entity)
	_rebuild_holder_ring()
	var c_launcher = _get_component(C_MissileLauncherClass)
	if c_launcher:
		if not c_launcher.missile_fired.is_connected(_on_missile_fired):
			c_launcher.missile_fired.connect(_on_missile_fired)
		if not c_launcher.missiles_stored_changed.is_connected(_update_missile_rack):
			c_launcher.missiles_stored_changed.connect(_update_missile_rack)
		_update_missile_rack(c_launcher.missiles_stored)


func complete_upgrade_animation() -> void:
	super.complete_upgrade_animation()
	_rebuild_holder_ring()
	var c_launcher = _get_component(C_MissileLauncherClass)
	if c_launcher:
		_update_missile_rack(c_launcher.missiles_stored)


func get_launch_position_for_slot(slot_index: int) -> Vector3:
	if slot_index < 0 or slot_index >= _rack_slots.size():
		var lp: Node3D = _body.get_node_or_null("VisualRoot/LaunchPoint") as Node3D
		return lp.global_position if lp and lp.is_inside_tree() else _body.global_position + Vector3.UP * 1.0
	var data: Dictionary = _rack_slots[slot_index]
	var lp_node: Marker3D = data.get("launch_point", null) as Marker3D
	if lp_node and lp_node.is_inside_tree():
		return lp_node.global_position
	return _body.global_position + Vector3.UP * 1.0


func _rebuild_holder_ring() -> void:
	if _holder_ring == null:
		return
	var c_launcher = _get_component(C_MissileLauncherClass)
	var capacity: int = c_launcher.missile_capacity if c_launcher else 5
	if capacity == _last_capacity and _rack_slots.size() == capacity:
		return
	_last_capacity = capacity

	_rack_slots.clear()
	var holder_cyl: CylinderMesh = CylinderMesh.new()
	holder_cyl.top_radius = HOLDER_CYL_RADIUS
	holder_cyl.bottom_radius = HOLDER_CYL_RADIUS
	holder_cyl.height = HOLDER_CYL_HEIGHT
	var holder_mat: StandardMaterial3D = StandardMaterial3D.new()
	holder_mat.albedo_color = Color(0.85, 0.45, 0.15, 1)
	holder_mat.emission_enabled = true
	holder_mat.emission = Color(0.75, 0.35, 0.08, 1)
	holder_mat.emission_energy_multiplier = 1.2

	for i in range(capacity):
		var slot_node: Node3D = _holder_ring.get_node_or_null("Slot%d" % i) as Node3D
		if slot_node == null:
			_create_slot_for_upgrade(i, holder_cyl, holder_mat)
			slot_node = _holder_ring.get_node_or_null("Slot%d" % i) as Node3D
		if slot_node == null:
			continue
		var launch_point: Marker3D = slot_node.get_node_or_null("LaunchPoint") as Marker3D
		var holder: MeshInstance3D = slot_node.get_node_or_null("Holder") as MeshInstance3D
		if holder == null:
			holder = MeshInstance3D.new()
			holder.name = "Holder"
			holder.mesh = holder_cyl
			holder.set_surface_override_material(0, holder_mat.duplicate())
			holder.position = Vector3(0, HOLDER_CYL_HEIGHT * 0.5, 0)
			holder.visible = false
			slot_node.add_child(holder)
		_rack_slots.append({"holder": holder, "launch_point": launch_point, "slot_node": slot_node})


func _create_slot_for_upgrade(index: int, holder_cyl: CylinderMesh, holder_mat: StandardMaterial3D) -> void:
	var HOLDER_RADIUS: float = 0.55
	var angle: float = index * TAU / 6 - PI / 2.0
	var x: float = HOLDER_RADIUS * cos(angle)
	var z: float = HOLDER_RADIUS * sin(angle)
	var slot_node: Node3D = Node3D.new()
	slot_node.name = "Slot%d" % index
	slot_node.position = Vector3(x, 0.0, z)
	_holder_ring.add_child(slot_node)
	var barrel_tube: CylinderMesh = CylinderMesh.new()
	barrel_tube.top_radius = 0.07
	barrel_tube.bottom_radius = 0.11
	barrel_tube.height = 0.5
	var barrel_breech: CylinderMesh = CylinderMesh.new()
	barrel_breech.top_radius = 0.11
	barrel_breech.bottom_radius = 0.13
	barrel_breech.height = 0.08
	var barrel_mat: StandardMaterial3D = StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.38, 0.36, 0.33, 1)
	barrel_mat.metallic = 0.85
	barrel_mat.roughness = 0.45
	var tube_mi: MeshInstance3D = MeshInstance3D.new()
	tube_mi.name = "BarrelTube"
	tube_mi.mesh = barrel_tube
	tube_mi.set_surface_override_material(0, barrel_mat.duplicate())
	tube_mi.position = Vector3(0, 0.25, 0)
	slot_node.add_child(tube_mi)
	var breech_mi: MeshInstance3D = MeshInstance3D.new()
	breech_mi.name = "BarrelBreech"
	breech_mi.mesh = barrel_breech
	breech_mi.set_surface_override_material(0, barrel_mat.duplicate())
	breech_mi.position = Vector3(0, 0.04, 0)
	slot_node.add_child(breech_mi)
	var lp: Marker3D = Marker3D.new()
	lp.name = "LaunchPoint"
	lp.position = Vector3(0, 0.5, 0)
	slot_node.add_child(lp)
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.name = "Holder"
	holder.mesh = holder_cyl
	holder.set_surface_override_material(0, holder_mat.duplicate())
	holder.position = Vector3(0, HOLDER_CYL_HEIGHT * 0.5, 0)
	holder.visible = false
	slot_node.add_child(holder)


func _update_missile_rack(count: int) -> void:
	if _last_capacity != _rack_slots.size():
		_rebuild_holder_ring()
	var capacity: int = _rack_slots.size()
	var fire_index: int = capacity - count
	for i in range(capacity):
		var holder: MeshInstance3D = _rack_slots[i].holder as MeshInstance3D
		var was_visible: bool = holder.visible
		var now_visible: bool = i >= fire_index
		holder.visible = now_visible
		if now_visible and not was_visible:
			_animate_missile_in(i)


func _animate_missile_in(slot_index: int) -> void:
	if slot_index >= _rack_slots.size():
		return
	var holder: MeshInstance3D = _rack_slots[slot_index].holder as MeshInstance3D
	var start_y: float = -HOLDER_CYL_HEIGHT - 0.15
	var end_y: float = HOLDER_CYL_HEIGHT * 0.5
	holder.position = Vector3(0, start_y, 0)
	var tween: Tween = holder.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "position", Vector3(0, end_y, 0), ANIMATE_IN_DURATION)


func _on_missile_fired(_from_pos: Vector3, _target_pos: Vector3, slot_index: int = 0) -> void:
	if _rack_slots.size() > 0 and slot_index >= 0 and slot_index < _rack_slots.size():
		var holder: MeshInstance3D = _rack_slots[slot_index].holder as MeshInstance3D
		if holder.visible:
			var mat: StandardMaterial3D = holder.get_active_material(0) as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = 5.0
				var timer: SceneTreeTimer = get_tree().create_timer(0.1)
				timer.timeout.connect(func() -> void:
					if _rack_slots.size() > 0 and is_instance_valid(holder):
						var reset_mat: StandardMaterial3D = holder.get_active_material(0) as StandardMaterial3D
						if reset_mat:
							reset_mat.emission_energy_multiplier = 1.2
				)
	var render_manager: Node = get_tree().root.get_node_or_null("StructureRenderManager")
	if render_manager and render_manager.has_method("pulse_structure"):
		render_manager.call("pulse_structure", _body, 0.1)
	var sfx_manager: Node = get_tree().root.get_node_or_null("SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", "laser_shot", -8.0)
