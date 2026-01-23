@tool
extends Node3D
class_name PowerGenerator
## Component that generates power

signal power_generated(amount: float)

@export var power_output: float = 10.0  # Power generated per second
@export var is_active: bool = true

var current_output: float = 0.0  # Actual output this frame


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_register_with_power_graph")


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_unregister_from_power_graph()


func _register_with_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.add_generator(self)


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_generator(self)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if is_active and _is_structure_built():
		generate_power()
	else:
		current_output = 0.0


## Check if the parent structure is fully built
func _is_structure_built() -> bool:
	# Navigate up: PowerGenerator -> PowerSource -> PowerNode -> Structure
	var power_node: Node = get_parent()
	if power_node:
		power_node = power_node.get_parent()  # Go from PowerSource to PowerNode
	if power_node:
		return power_node.get("is_enabled") == true
	return true  # If we can't find the structure, assume built


## Generate power and store in parent source
func generate_power() -> void:
	if not is_active:
		current_output = 0.0
		return
	
	current_output = power_output
	
	# Find parent source to store power
	var parent: Node = get_parent()
	if parent is PowerSource:
		var source: PowerSource = parent as PowerSource
		var available_space: float = source.max_storage - source.current_storage
		
		if available_space > 0:
			var power_to_store: float = minf(power_output * get_process_delta_time(), available_space)
			source.store_power(power_to_store)
			power_generated.emit(power_to_store)
		else:
			# Handle excess power - send to other sources in the grid
			var excess: float = power_output * get_process_delta_time()
			if PowerGraphManager:
				PowerGraphManager.handle_generator_excess(self, excess)


## Set the active state
func set_active(active: bool) -> void:
	is_active = active
	if not active:
		current_output = 0.0
