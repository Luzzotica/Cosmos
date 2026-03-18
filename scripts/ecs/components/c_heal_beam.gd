class_name C_HealBeam
extends Component
## ECS data component for repair robot heal beam stats and runtime state.
## RepairRobotHealSystem drives healing; uses small blue laser visual.

@export var heal_rate: float = 8.0
@export var heal_range: float = 4.0
@export var beam_color: Color = Color(0.2, 0.5, 1.0, 0.9)
@export var attack_cooldown: float = 0.5

var cooldown_remaining: float = 0.0
