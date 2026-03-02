extends BaseStructure
class_name PowerNodeStructure
## Power Node - Relay structure for extending power grid


func _ready() -> void:
	building_type = "power_node"
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		return
	
	var powered: bool = has_operational_power()
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", powered)
