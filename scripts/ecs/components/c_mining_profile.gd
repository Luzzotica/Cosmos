class_name C_MiningProfile
extends Component
## ECS data component for mining station config.
## Mining logic moved to MiningSystem.

@export var mining_radius: float = 12.5
@export var mining_interval: float = 3.0
@export var mine_amount: float = 5.0

## Reference to current target asteroid (Node3D)
var target_asteroid_ref: WeakRef = null
