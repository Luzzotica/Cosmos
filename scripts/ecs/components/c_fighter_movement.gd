class_name C_FighterMovement
extends Component
## ECS component for fighter movement params: turn rate, avoidance config.
## Movement-only; collision damage lives in C_CollisionDamage.

@export var turn_rate_deg: float = 100.0
## How far the avoidance scanner sees.
@export var avoid_radius: float = 16.0
## Ship collision radius for local-space avoidance.
@export var ship_radius: float = 0.6
## Assumed obstacle radius for local-space avoidance.
@export var obstacle_radius: float = 2.0
## Magnitude of lateral push when avoiding.
@export var steer_force: float = 1.5
## Within this distance of nearest in-path obstacle, slow down to allow swerving.
@export var obstacle_slow_dist: float = 6.0
## Minimum speed multiplier when very close to obstacles.
@export var min_speed_near_obstacle: float = 0.5
## Offset target structure position perpendicular to ship-target line. Enemies approach from the side.
@export var target_offset_length: float = 3.0
@export var target_offset_side: float = 1.0
