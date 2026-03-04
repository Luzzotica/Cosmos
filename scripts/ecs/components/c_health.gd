class_name C_Health
extends Component
## ECS data component for health. Shared by enemies and structures.

@export var current: float = 100.0
@export var maximum: float = 100.0
## Damage type -> multiplier (1.0 = normal, 0.0 = immune, <1.0 = resistant)
@export var resistance_profile: Dictionary = {}

func _init(p_max: float = 100.0, p_current: float = -1.0) -> void:
	maximum = p_max
	current = p_current if p_current >= 0.0 else p_max
