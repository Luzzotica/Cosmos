class_name C_BeamWeapon
extends Component
## ECS data component for beam weapon stats and runtime state.
## BeamWeaponSystem drives attacks; attack_fired lets ship visuals play firing animations.

signal attack_fired(from_pos: Vector3, target_pos: Vector3, beam_color: Color)

@export var damage: float = 10.0
@export var attack_range: float = 15.0
@export var attack_cooldown: float = 3.0
@export var beam_color: Color = Color(1.0, 0.25, 0.2, 0.95)
@export var damage_type: String = "physical"

var cooldown_remaining: float = 0.0
