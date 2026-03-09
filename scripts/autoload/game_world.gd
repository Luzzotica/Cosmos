extends Node
## Holds references to the current game world's sun light and power lines container.
## Set by Main in _ready. Used by PowerGraphManager, SolarPanelSystem, etc.

var sun_light: DirectionalLight3D = null
var power_lines_parent: Node3D = null


func set_world(sun: DirectionalLight3D, lines_parent: Node3D) -> void:
	sun_light = sun
	power_lines_parent = lines_parent


func clear_world() -> void:
	sun_light = null
	power_lines_parent = null
