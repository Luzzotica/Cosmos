class_name C_Construction
extends Component
## ECS data component for structure build state.
## Replaces ConstructionComponent node-based component.

signal build_progress_changed(progress: float)

var _is_built: bool = false
@export var is_built: bool = false:
	get:
		return _is_built
	set(v):
		if _is_built != v:
			var old: bool = _is_built
			_is_built = v
			property_changed.emit(self, "is_built", old, v)

var _build_progress: float = 0.0
@export var build_progress: float = 0.0:
	get:
		return _build_progress
	set(v):
		var clamped: float = clampf(v, 0.0, 1.0)
		if _build_progress != clamped:
			_build_progress = clamped
			build_progress_changed.emit(_build_progress)
@export var requires_power: bool = true
@export var build_power_cost: float = 10.0
@export var construction_time: float = 3.0
@export var instant_build: bool = false

## True once power cost has been consumed to start building
var build_power_paid: bool = false
