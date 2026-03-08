class_name C_PowerNode
extends Component
## ECS data component for power grid routing.
## Replaces PowerNode node-based component.

enum NodeType {
	SOURCE,  # Generates/stores power (solar panels)
	NODE,    # Pure relay (dedicated power nodes)
	LEAF     # Consumes power (mining stations, turrets, monolith)
}

@export var node_type: NodeType = NodeType.NODE
@export var max_connection_distance: float = 15.0
@export var max_connections: int = 4
var _is_enabled: bool = true
@export var is_enabled: bool = true:
	get:
		return _is_enabled
	set(v):
		if _is_enabled != v:
			var old: bool = _is_enabled
			_is_enabled = v
			property_changed.emit(self, "is_enabled", old, v)

## Connected entity IDs (Entity.get_instance_id() for lookup)
var connected_entity_ids: Array[int] = []
var is_powered: bool = false

## Reference to structure node for position/line-of-sight
var structure_node: Node3D = null
