class_name C_Team
extends Component
## ECS data component for team affiliation. Shared by enemies and structures.

@export var team: String = "player"

func _init(p_team: String = "player") -> void:
	team = p_team
