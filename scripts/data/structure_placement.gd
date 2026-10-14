@tool
extends Resource
class_name StructurePlacement
## Data class for structure placement in a map

@export var building_type: String = "solar_panel"
@export var position: Vector3 = Vector3.ZERO
@export var is_pre_built: bool = true
## When type is monolith: counts for win conditions and end-dialogue monolith tiers. Default true when omitted in JSON.
@export var victory_monolith: bool = true
