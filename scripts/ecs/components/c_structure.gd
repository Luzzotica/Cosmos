class_name C_Structure
extends Component
## ECS data component for player structures. Holds ref to the structure node.

@export var building_type: String = ""
@export var is_destroyed: bool = false
## Reference to the BaseStructure (Node3D) for sync and gameplay
var structure_node: Node3D = null
