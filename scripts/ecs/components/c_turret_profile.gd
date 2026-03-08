class_name C_TurretProfile
extends Component
## ECS data component for turret structures. Data-driven from BuildingData.

@export var attack_range: float = 35.0
@export var fire_rate: float = 1.0  # Shots per second
@export var damage: float = 10.0
@export var beam_color: Color = Color(0.2, 0.9, 1.0, 0.95)
## Cooldown remaining until next shot (seconds)
var fire_timer: float = 0.0
