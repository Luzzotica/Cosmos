@tool
extends Node3D
class_name ConstructionComponent
## Component that handles structure construction progress.
## Creates a temporary enabled PowerNode with a PowerUser child to draw
## construction power while the structure's main PowerNode stays disabled.

signal construction_progress_changed(progress: float)
signal construction_completed

@export var construction_time: float = 3.0
@export var requires_power: bool = true
@export var build_power_cost: float = 10.0

var build_progress: float = 0.0
var is_built: bool = false
var _power_paid: bool = false

var _power_node: Node3D = null  # Main PowerNode sibling (disabled during construction)
var _construction_power_node: PowerNode = null  # Temporary enabled PowerNode for construction
var _construction_power_user: PowerUser = null
var on_construction_complete: Callable = Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	var parent: Node = get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling.has_method("can_accept_more_connections"):
				_power_node = sibling
				break
	
	if not is_built and requires_power:
		# Defer entire creation: parent is busy during _ready; also avoids crash when
		# parent may be freed/replaced during scene load (e.g. tutorial level).
		call_deferred("_create_construction_power_node")


func _create_construction_power_node() -> void:
	if is_built or not requires_power:
		return
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	_construction_power_node = PowerNode.new()
	_construction_power_node.max_connection_distance = _power_node.max_connection_distance if _power_node else PowerNode.CONNECTION_RANGE
	_construction_power_node.max_connections = 1
	_construction_power_node.is_enabled = true

	_construction_power_user = PowerUser.new()
	_construction_power_user.use_power_cost = build_power_cost
	_construction_power_user.power_buffer_capacity = build_power_cost + 5.0
	_construction_power_user.is_construction_user = true
	_construction_power_node.add_child(_construction_power_user)

	parent.add_child(_construction_power_node)
	if PowerGraphManager:
		call_deferred("_register_construction_power_node")


func _register_construction_power_node() -> void:
	if _construction_power_node and is_instance_valid(_construction_power_node) and _construction_power_node.is_inside_tree() and PowerGraphManager:
		PowerGraphManager.add_node(_construction_power_node)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if is_built:
		return
	
	var can_build: bool = false
	
	if not requires_power:
		can_build = true
	elif _construction_power_node and _construction_power_node.get("connected_nodes"):
		var connected: Array = _construction_power_node.get("connected_nodes")
		if connected.size() > 0:
			if _power_paid:
				can_build = true
			elif _construction_power_user and _construction_power_user.consume_power():
				_power_paid = true
				can_build = true
	
	if can_build:
		build_progress += delta / maxf(construction_time, 0.001)
		construction_progress_changed.emit(build_progress)
		
		if build_progress >= 1.0:
			_complete_construction()


func _complete_construction() -> void:
	is_built = true
	build_progress = 1.0
	
	_free_construction_power_node()
	
	if _power_node:
		_power_node.is_enabled = true
		if _power_node.has_method("invalidate_type_cache"):
			_power_node.invalidate_type_cache()
	
	construction_completed.emit()
	
	if on_construction_complete.is_valid():
		on_construction_complete.call()


## Set construction as already complete (for starter buildings)
func set_built() -> void:
	is_built = true
	build_progress = 1.0
	
	_free_construction_power_node()
	
	if _power_node:
		_power_node.is_enabled = true
		if _power_node.has_method("invalidate_type_cache"):
			_power_node.invalidate_type_cache()


func _free_construction_power_node() -> void:
	if _construction_power_node and is_instance_valid(_construction_power_node):
		_construction_power_node.queue_free()
	_construction_power_node = null
	_construction_power_user = null


## Get construction progress (0.0 to 1.0)
func get_progress() -> float:
	return clampf(build_progress, 0.0, 1.0)
