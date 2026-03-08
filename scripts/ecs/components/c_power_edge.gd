class_name C_PowerEdge
extends Component
## ECS component for a power line edge between two node entities.
## Per PERFORMANCE_OPTIMIZATION: use bool properties for is_blocked, is_flashing (frequently changing).

var entity_id_a: int = 0
var entity_id_b: int = 0
var _is_blocked: bool = false
var is_blocked: bool:
	get:
		return _is_blocked
	set(v):
		if _is_blocked != v:
			var old: bool = _is_blocked
			_is_blocked = v
			property_changed.emit(self, "is_blocked", old, v)
var is_flashing: bool = false
## Reference to the line Node3D (mesh + Area3D) for visual updates
var line_node: Node3D = null
