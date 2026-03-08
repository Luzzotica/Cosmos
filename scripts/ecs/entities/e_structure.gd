extends Entity
class_name E_Structure
## Generic structure entity. Use for all structure types; behavior scripts drive entity-specific logic.

const StructureEntityUtils = preload("res://scripts/ecs/structure_entity_utils.gd")

signal destroyed
signal minerals_extracted(amount: int)
signal target_acquired(target: Node3D)
signal target_lost
signal fired(target: Node3D, damage: float)

@export var building_type: String = ""
@export var spawned_structure: bool = false
@export_group("Placement Preview")
@export var placement_preview_exclude_mesh_names: PackedStringArray = PackedStringArray()

## Optional: set before _register_with_ecs for monolith to configure C_MonolithCharge.power_required
var _pending_monolith_power_required: float = -1.0

var is_destroyed: bool = false
var max_connections: int = 4
var selectable_component: Node


func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	call_deferred("_register_with_ecs")


func _register_with_ecs() -> void:
	if not ECS or not ECS.world:
		return
	ECS.world.add_entity(self, null, false)
	if spawned_structure:
		var c_const: C_Construction = get_component(C_Construction) as C_Construction
		if c_const:
			c_const.instant_build = true
	var c_charge: C_MonolithCharge = get_component(C_MonolithCharge) as C_MonolithCharge
	if c_charge and _pending_monolith_power_required > 0:
		c_charge.power_required = _pending_monolith_power_required
	var c_pn: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
	if c_pn:
		set("max_connections", c_pn.max_connections)
	var behavior: Node = get_node_or_null("StructureBehavior")
	if behavior and behavior.has_method("setup_after_ecs"):
		behavior.setup_after_ecs()
	if behavior and behavior.has_method("apply_post_register"):
		behavior.apply_post_register()


func on_ready() -> void:
	_set_structure_node_on_components()
	_sync_transform_from_scene()


func _set_structure_node_on_components() -> void:
	for comp in components.values():
		if comp and "structure_node" in comp:
			comp.structure_node = self


func _sync_transform_from_scene() -> void:
	var c_tr: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
	if c_tr:
		c_tr.position = get("global_position")
		c_tr.rotation = get("rotation")


func _process(_delta: float) -> void:
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _on_construction_completed() -> void:
	var behavior: Node = get_node_or_null("StructureBehavior")
	if behavior and behavior.has_method("on_construction_completed"):
		behavior.on_construction_completed()
	set("scale", Vector3.ONE)


func is_built() -> bool:
	return StructureEntityUtils.is_built(self)


func has_operational_power() -> bool:
	return StructureEntityUtils.has_operational_power(self)


func take_damage(amount: float) -> void:
	StructureEntityUtils.take_damage(self, amount)


func take_damage_event(event_payload: Dictionary) -> float:
	return StructureEntityUtils.take_damage_event(self, event_payload)


func can_accept_more_connections() -> bool:
	return StructureEntityUtils.can_accept_more_connections(self)


func get_node_type() -> int:
	return StructureEntityUtils.get_node_type(self)


func get_max_connection_distance() -> float:
	return StructureEntityUtils.get_max_connection_distance(self)


func can_connect_to(other: Node3D) -> bool:
	return StructureEntityUtils.can_connect_to(self, other)


func connect_node(other: Node3D) -> void:
	StructureEntityUtils.connect_node(self, other)


func is_valid_connection_target() -> bool:
	return StructureEntityUtils.is_valid_connection_target(self)


func get_team() -> String:
	return StructureEntityUtils.get_team(self)


func get_selection_name() -> String:
	return StructureEntityUtils.get_selection_name(self, building_type)


func get_selection_details() -> Dictionary:
	var extra_stats: Array = []
	var behavior: Node = get_node_or_null("StructureBehavior")
	if behavior and behavior.has_method("get_extra_selection_stats"):
		extra_stats = behavior.get_extra_selection_stats()
	return StructureEntityUtils.get_selection_details(self, building_type, extra_stats)


func is_sun_tracking_active() -> bool:
	var behavior: Node = get_node_or_null("StructureBehavior")
	if behavior and behavior.has_method("is_sun_tracking_active"):
		return behavior.is_sun_tracking_active()
	return true


func get_charge_percentage() -> float:
	var c_charge: C_MonolithCharge = get_component(C_MonolithCharge) as C_MonolithCharge
	if c_charge:
		return c_charge.get_charge_percentage()
	return 0.0


func is_fully_charged() -> bool:
	var c_charge: C_MonolithCharge = get_component(C_MonolithCharge) as C_MonolithCharge
	if c_charge:
		return c_charge.is_fully_charged()
	return false


func play_attack_visuals(target_pos: Vector3, beam_color: Color) -> void:
	var behavior: Node = get_node_or_null("StructureBehavior")
	if behavior and behavior.has_method("play_attack_visuals"):
		behavior.play_attack_visuals(target_pos, beam_color)


func get_target() -> Node3D:
	var c_targeting: C_Targeting = get_component(C_Targeting) as C_Targeting
	return c_targeting.target_node if c_targeting else null


func is_active() -> bool:
	return is_built() and has_operational_power()


func get_target_position() -> Vector3:
	var c_mining: C_MiningProfile = get_component(C_MiningProfile) as C_MiningProfile
	if c_mining and c_mining.target_asteroid_ref:
		var ref = c_mining.target_asteroid_ref.get_ref()
		if ref is Node3D:
			return ref.global_position
	return get("global_position") if get("global_position") != null else Vector3.ZERO


func _exit_tree() -> void:
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
