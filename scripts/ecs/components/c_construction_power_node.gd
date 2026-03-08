class_name C_ConstructionPowerNode
extends Component
## First-class power node during construction. Graph treats it identically to C_PowerNode.
## Construction structures act as leaf (max_connections=1). Tracks preview connections via
## On build complete, connections are copied to C_PowerNode and this component is removed.

## Fixed as leaf - construction structures only consume power during build.
const NODE_TYPE_LEAF: int = 2  # C_PowerNode.NodeType.LEAF

var max_connection_distance: float = 15.0
## Max connections when built; construction node is always leaf (1).
## Real connections during construction (graph writes here).
var connected_entity_ids: Array[int] = []
## Preview connections computed via PowerGraph.compute_preview_connections; rendered as dim lines.
var preview_connected_entity_ids: Array[int] = []
var is_powered: bool = false

## Fixed at 1 - construction nodes are always leaf.
var max_connections: int = 1

var _is_enabled: bool = true
var is_enabled: bool = true:
	get:
		return _is_enabled
	set(v):
		if _is_enabled != v:
			var old: bool = _is_enabled
			_is_enabled = v
			property_changed.emit(self, "is_enabled", old, v)

## Reference to structure node for position/line-of-sight
var structure_node: Node3D = null
