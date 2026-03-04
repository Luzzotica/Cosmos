class_name C_EnemyState
extends Component
## ECS data component for enemy runtime state.

@export var speed: float = 6.0
@export var damage: float = 10.0
@export var attack_range: float = 15.0
@export var attack_cooldown: float = 3.0
@export var is_destroyed: bool = false
@export var reward_minerals: int = 10
@export var display_name: String = "Enemy Ship"
@export var enemy_id: String = "enemy_standard"
