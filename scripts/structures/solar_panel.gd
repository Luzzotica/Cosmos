extends BaseStructure
class_name SolarPanel
## Solar Panel - Generates and stores power

var power_source: PowerSource
var power_generator: PowerGenerator
var is_active: bool = false
var _is_starter_panel: bool = false


func _ready() -> void:
	building_type = "solar_panel"
	super._ready()
	_setup_power_components()


func _setup_power_components() -> void:
	# Find power components
	if power_node:
		for child in power_node.get_children():
			if child is PowerSource:
				power_source = child
				for source_child in power_source.get_children():
					if source_child is PowerGenerator:
						power_generator = source_child


func set_starter_panel(is_starter: bool) -> void:
	_is_starter_panel = is_starter
	super.set_starter_panel(is_starter)
	
	if is_starter and power_source:
		# Start with 50% power
		power_source.current_storage = power_source.max_storage * 0.5
		is_active = true


func _process(_delta: float) -> void:
	if not is_built():
		return
	
	is_active = true
