class_name C_MiningStation
extends Component
## ECS data component for mining stations. Holds mining config and target reference.
## Use C_Structure.structure_node for the body reference.

@export var mining_radius: float = 12.5
@export var mining_interval: float = 2.0
@export var mine_amount: float = 15.0
var mining_timer: float = 0.0
var target_entity: Entity = null
var is_mining: bool = false
