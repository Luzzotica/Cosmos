class_name C_RepairRobotMovement
extends Component
## ECS component for repair robot movement params. Matches fighter movement.
## RepairRobotMovementSystem drives movement when state is HEALING or FLY_TO_STATION.

@export var speed: float = 6.0
@export var turn_rate_deg: float = 100.0
@export var avoid_radius: float = 5.0
@export var ship_radius: float = 0.4
@export var obstacle_radius: float = 1.2
@export var steer_force: float = 1.5
@export var obstacle_slow_dist: float = 3.0
@export var min_speed_near_obstacle: float = 0.5
@export var target_offset_length: float = 0.0
@export var target_offset_side: float = 0.0
