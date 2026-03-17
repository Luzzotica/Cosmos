class_name C_Targeting
extends Component
## ECS data component for enemy targeting state.

## Target entity id (for lookup) or direct node ref when entities reference nodes
var target_node: Node3D = null
## Optional hover position (e.g. power line midpoint for saboteurs). Use Vector3.INF as unset.
var target_position: Vector3 = Vector3.INF
@export var retarget_timer: float = 0.0
@export var fallback_position: Vector3 = Vector3.ZERO
@export var forward_direction: Vector3 = Vector3.FORWARD
