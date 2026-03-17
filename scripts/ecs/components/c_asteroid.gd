class_name C_Asteroid
extends Component
## ECS data component for asteroids. Holds mineral data and body reference.

const MIN_SIZE: float = 2.0
const MAX_SIZE: float = 4.0
const MINERAL_DENSITY: float = 100.0

@export var size: float = 3.0
@export var total_minerals: float = 30.0
@export var remaining_minerals: float = 30.0
@export var is_depleted: bool = false
## Reference to the AsteroidBody Node3D for visuals and collision
var body_node: Node3D = null
