class_name C_ReflectorMovement
extends Component
## Reflector-specific movement: straight to nearest target, stop and fire.
## No strafing or flybys; minimal obstacle avoidance.


@export var turn_rate_deg: float = 90.0
## How far the avoidance scanner sees.
@export var avoid_radius: float = 14.0
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
