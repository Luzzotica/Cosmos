class_name C_AttackProfile
extends Component
## ECS data component holding attack behavior config.

@export var profile: Dictionary = {}
@export var ability_profile: Dictionary = {}
@export var beam_color: Color = Color(1.0, 0.25, 0.2, 0.95)
@export var cooldown_remaining: float = 0.0
@export var damage_type: String = "physical"
