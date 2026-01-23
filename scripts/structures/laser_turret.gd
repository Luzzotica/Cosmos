extends BaseStructure
class_name LaserTurret
## Laser Turret - Defensive structure that attacks enemies

signal target_acquired(target: Node3D)
signal target_lost
signal fired(target: Node3D, damage: float)

@export var attack_range: float = 100.0
@export var fire_rate: float = 1.0  # Shots per second
@export var damage: float = 10.0

var power_user: PowerUser
var target: Node3D = null
var rotation_angle: float = 0.0
var fire_timer: float = 0.0

@onready var turret_base: MeshInstance3D = $TurretBase
@onready var turret_barrel: MeshInstance3D = $TurretBarrel


func _ready() -> void:
	building_type = "laser_turret"
	super._ready()
	_setup_power_user()


func _setup_power_user() -> void:
	if power_node:
		for child in power_node.get_children():
			if child is PowerUser:
				power_user = child
				break


func _process(delta: float) -> void:
	if not is_built():
		return
	
	# Update fire timer
	fire_timer -= delta
	
	# Only operate if powered
	if power_user and power_user.has_power:
		_find_target()
		_update_rotation()
		_try_attack()
	else:
		target = null


func _find_target() -> void:
	# Clear target if destroyed or out of range
	if target != null:
		if not is_instance_valid(target):
			target = null
			target_lost.emit()
		elif _is_target_destroyed(target):
			target = null
			target_lost.emit()
		elif global_position.distance_to(target.global_position) > attack_range:
			target = null
			target_lost.emit()
	
	# Find new target if needed
	if target == null:
		target = _find_closest_enemy()
		if target:
			target_acquired.emit(target)


func _find_closest_enemy() -> Node3D:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return null
	
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if not enemies_parent:
		return null
	
	var closest_distance: float = INF
	var closest_enemy: Node3D = null
	
	for child in enemies_parent.get_children():
		if _is_target_destroyed(child):
			continue
		
		var distance: float = global_position.distance_to(child.global_position)
		if distance <= attack_range and distance < closest_distance:
			closest_distance = distance
			closest_enemy = child
	
	return closest_enemy


func _is_target_destroyed(t: Node3D) -> bool:
	if t.has_method("is_destroyed"):
		return t.is_destroyed
	if t.get("is_destroyed") != null:
		return t.is_destroyed
	return false


func _update_rotation() -> void:
	if target == null:
		return
	
	var target_pos: Vector3 = target.global_position
	var direction: Vector3 = target_pos - global_position
	rotation_angle = atan2(direction.x, direction.z)
	
	if turret_barrel:
		turret_barrel.rotation.y = rotation_angle


func _try_attack() -> void:
	if fire_timer > 0 or target == null:
		return
	
	if not power_user or not power_user.consume_power():
		return
	
	# Fire!
	fire_timer = 1.0 / fire_rate
	
	# Deal damage to target
	if target.has_method("take_damage"):
		target.take_damage(damage)
	
	fired.emit(target, damage)
	
	# TODO: Create laser beam visual effect


## Get current target
func get_target() -> Node3D:
	return target


## Check if turret is active and powered
func is_active() -> bool:
	return is_built() and power_user and power_user.has_power
