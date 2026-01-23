extends Node3D
class_name TeamComponent
## Component that identifies team membership for targeting

enum Team {
	PLAYER,
	ENEMY,
	NEUTRAL
}

@export var team: Team = Team.PLAYER
@export var detection_range: float = 300.0
@export var attack_range: float = 200.0


## Get team as string for comparison
func get_team_string() -> String:
	match team:
		Team.PLAYER:
			return "player"
		Team.ENEMY:
			return "enemy"
		Team.NEUTRAL:
			return "neutral"
	return "unknown"


## Check if another team component is hostile
func is_hostile_to(other: TeamComponent) -> bool:
	if team == Team.NEUTRAL or other.team == Team.NEUTRAL:
		return false
	return team != other.team


## Check if position is within detection range
func is_in_detection_range(position: Vector3) -> bool:
	var parent: Node3D = get_parent() as Node3D
	if not parent:
		return false
	return parent.global_position.distance_to(position) <= detection_range


## Check if position is within attack range
func is_in_attack_range(position: Vector3) -> bool:
	var parent: Node3D = get_parent() as Node3D
	if not parent:
		return false
	return parent.global_position.distance_to(position) <= attack_range


## Find hostile components in range
func find_hostile_in_range(components: Array) -> Array:
	var hostiles: Array = []
	var parent: Node3D = get_parent() as Node3D
	if not parent:
		return hostiles
	
	for component in components:
		if not is_instance_valid(component):
			continue
		
		var other_team: TeamComponent = _get_team_component(component)
		if other_team and is_hostile_to(other_team):
			var distance: float = parent.global_position.distance_to(component.global_position)
			if distance <= detection_range:
				hostiles.append(component)
	
	return hostiles


## Find closest hostile in attack range
func find_closest_hostile_in_attack_range(components: Array) -> Node3D:
	var parent: Node3D = get_parent() as Node3D
	if not parent:
		return null
	
	var closest: Node3D = null
	var closest_distance: float = INF
	
	for component in components:
		if not is_instance_valid(component):
			continue
		
		var other_team: TeamComponent = _get_team_component(component)
		if other_team and is_hostile_to(other_team):
			var distance: float = parent.global_position.distance_to(component.global_position)
			if distance <= attack_range and distance < closest_distance:
				closest = component
				closest_distance = distance
	
	return closest


func _get_team_component(node: Node3D) -> TeamComponent:
	for child in node.get_children():
		if child is TeamComponent:
			return child
	return null
