class_name C_ConstructionPowerNode
extends Component
## Pseudo-node during construction. Saves C_PowerNode's original max_connections, overrides it to 1
## so the graph treats the structure as a leaf. Tracks preview connections via PowerGraph using
## saved_max_connections; these are rendered as dim power lines. On build complete, connections
## are copied to C_PowerNode and max_connections is restored.

## Fixed as leaf - construction structures only consume power during build.
const NODE_TYPE_LEAF: int = 2  # C_PowerNode.NodeType.LEAF

var max_connection_distance: float = 15.0
## Original C_PowerNode.max_connections, restored when build completes.
var saved_max_connections: int = 4
## Pseudo connections computed via PowerGraph.compute_preview_connections; rendered as dim lines.
var preview_connected_entity_ids: Array[int] = []
var is_powered: bool = false

## Reference to structure node for position/line-of-sight
var structure_node: Node3D = null


## Set C_PowerNode to leaf mode (max_connections=1) so the graph sees it as leaf.
func _apply_construction_mode(c_power_node: C_PowerNode) -> void:
	if c_power_node:
		c_power_node.max_connections = 1
