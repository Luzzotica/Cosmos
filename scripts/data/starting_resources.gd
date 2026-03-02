@tool
extends Resource
class_name StartingResources
## Optional per-map overrides for initial economy state.

@export var override_defaults: bool = false
@export var minerals: int = 10000
@export var energy: float = 100.0
@export var energy_capacity: float = 100.0
