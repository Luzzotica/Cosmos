@tool
extends Node3D
class_name ConstructionComponent
## Component that handles structure construction progress
## Requires power to build - creates a temporary PowerUser during construction

signal construction_progress_changed(progress: float)
signal construction_completed

@export var construction_time: float = 3.0  # Seconds to build
@export var requires_power: bool = true
@export var build_power_cost: float = 10.0  # One-time power cost to start building

var build_progress: float = 0.0
var is_built: bool = false
var _power_paid: bool = false  # True once power cost has been consumed

var _power_node: Node3D = null  # PowerNode sibling
var _construction_power_user: PowerUser = null  # Temporary PowerUser for construction
var on_construction_complete: Callable = Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	# Find power node sibling
	var parent: Node = get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling.has_method("can_accept_more_connections"):
				_power_node = sibling
				break
	
	# Create construction power user if not already built
	if not is_built and requires_power and _power_node:
		_create_construction_power_user()


func _create_construction_power_user() -> void:
	_construction_power_user = PowerUser.new()
	_construction_power_user.use_power_cost = build_power_cost
	_construction_power_user.power_buffer_capacity = build_power_cost + 5.0  # Buffer slightly larger than cost
	_construction_power_user.is_construction_user = true
	_power_node.add_child(_construction_power_user)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if is_built:
		return
	
	# Check if we can build
	var can_build: bool = false
	
	if not requires_power:
		can_build = true
	elif _power_node and _power_node.get("connected_nodes"):
		var connected: Array = _power_node.get("connected_nodes")
		if connected.size() > 0:
			# Already paid for construction - just build
			if _power_paid:
				can_build = true
			# Need to pay power cost once to start building
			elif _construction_power_user and _construction_power_user.consume_power():
				_power_paid = true
				can_build = true
	
	if can_build:
		build_progress += delta / construction_time
		construction_progress_changed.emit(build_progress)
		
		if build_progress >= 1.0:
			_complete_construction()


func _complete_construction() -> void:
	is_built = true
	build_progress = 1.0
	
	# Remove construction power user
	if _construction_power_user:
		_construction_power_user.queue_free()
		_construction_power_user = null
	
	# Enable the power node after construction and invalidate type cache
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
	
	# Remove construction power user if it exists
	if _construction_power_user:
		_construction_power_user.queue_free()
		_construction_power_user = null
	
	if _power_node:
		_power_node.is_enabled = true
		if _power_node.has_method("invalidate_type_cache"):
			_power_node.invalidate_type_cache()


## Get construction progress (0.0 to 1.0)
func get_progress() -> float:
	return clampf(build_progress, 0.0, 1.0)
