extends RefCounted
class_name EnemyAbilityBehavior
## Special abilities (sabotage / commander aura).

var ability_type: String = ""
var sabotage_cooldown: float = 10.0
var disable_duration: float = 8.0
var aura_radius: float = 45.0
var aura_speed_multiplier: float = 1.2
var aura_damage_multiplier: float = 1.2
var aura_attack_multiplier: float = 1.25
var aura_retarget_interval: float = 0.2

var _cooldown_remaining: float = 0.0


func configure(profile: Dictionary) -> void:
	ability_type = String(profile.get("type", ability_type))
	sabotage_cooldown = float(profile.get("sabotage_cooldown", sabotage_cooldown))
	disable_duration = float(profile.get("disable_duration", disable_duration))
	aura_radius = float(profile.get("aura_radius", aura_radius))
	aura_speed_multiplier = float(profile.get("aura_speed_multiplier", aura_speed_multiplier))
	aura_damage_multiplier = float(profile.get("aura_damage_multiplier", aura_damage_multiplier))
	aura_attack_multiplier = float(profile.get("aura_attack_multiplier", aura_attack_multiplier))
	aura_retarget_interval = float(profile.get("aura_retarget_interval", aura_retarget_interval))


func tick(delta: float, enemy: Node3D, target: Node3D) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if target != null and not is_instance_valid(target):
		return
	match ability_type:
		"power_sabotage":
			_try_sabotage(enemy, target)
		"commander_aura":
			_apply_commander_aura(enemy)
		_:
			return


func _try_sabotage(enemy: Node3D, target: Node3D) -> void:
	if _cooldown_remaining > 0.0 or target == null:
		return
	var power_node: Node = target.get("power_node")
	if power_node == null:
		return
	if not power_node.get("is_enabled"):
		return
	var graph: Node = enemy.get_node_or_null("/root/PowerGraphManager")
	if graph == null or not graph.has_method("disable_node"):
		return
	graph.call("disable_node", power_node)
	var timer: SceneTreeTimer = enemy.get_tree().create_timer(maxf(disable_duration, 0.1))
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(power_node):
			return
		if graph and is_instance_valid(graph) and graph.has_method("enable_node"):
			graph.call("enable_node", power_node)
	)
	_cooldown_remaining = maxf(sabotage_cooldown, 0.25)


func _apply_commander_aura(enemy: Node3D) -> void:
	var manager: Node = enemy.get_node_or_null("/root/EnemyManager")
	if manager == null or not manager.has_method("register_commander_aura"):
		return
	manager.call("register_commander_aura", enemy, {
		"radius": aura_radius,
		"speed_multiplier": aura_speed_multiplier,
		"damage_multiplier": aura_damage_multiplier,
		"attack_cooldown_multiplier": 1.0 / maxf(aura_attack_multiplier, 0.01),
		"retarget_interval_override": aura_retarget_interval,
		"target_priority_multiplier": 1.4
	})
