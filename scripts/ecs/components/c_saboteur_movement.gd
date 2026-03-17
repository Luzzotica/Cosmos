class_name C_SaboteurMovement
extends Component
## Saboteur-specific movement: turn rate, avoidance, approach behavior.
## Distinct from fighters; tuned for sneaky approach to power lines.


@export var turn_rate_deg: float = 120.0
## How far the avoidance scanner sees. Smaller than fighters so it gets close to structures.
@export var avoid_radius: float = 12.0
## Ship collision radius for local-space avoidance.
@export var ship_radius: float = 0.6
## Assumed obstacle radius. Small = only avoid when nearly on collision course.
@export var obstacle_radius: float = 2.0
## Magnitude of lateral push when avoiding.
@export var steer_force: float = 1.5
## Within this distance of target, skip avoidance. Small (0.2) = only when on the line.
@export var safe_distance: float = 0.2
## Distance at which to start decelerating for a smooth arrival.
@export var approach_decel_dist: float = 4.0
## Minimum speed multiplier when close (0.15 = gentle coast into transform).
@export var min_approach_speed: float = 0.15
## Within this distance of nearest in-path obstacle, slow down to allow swerving.
@export var obstacle_slow_dist: float = 6.0
## Minimum speed multiplier when very close to obstacles.
@export var min_speed_near_obstacle: float = 0.5
