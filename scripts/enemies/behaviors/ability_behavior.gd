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
	var node_to_disable: Node = target.get("power_node")
	if node_to_disable == null:
		node_to_disable = target
	if not _has_power_node(node_to_disable):
		return
	if not _is_node_enabled(node_to_disable):
		return
	if not PowerGraph or not PowerGraph.has_method("set_node_enabled"):
		return
	var struct: Node3D = node_to_disable if node_to_disable.get("building_type") != null else node_to_disable.get_parent() as Node3D
	if struct == null:
		return
	PowerGraph.set_node_enabled(struct, false)
	var timer: SceneTreeTimer = enemy.get_tree().create_timer(maxf(disable_duration, 0.1))
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(target):
			return
		var n: Node = target.get("power_node") if target.get("power_node") != null else target
		var s: Node3D = n as Node3D if n and n.get("building_type") != null else (n.get_parent() as Node3D) if n else null
		if PowerGraph and s:
			PowerGraph.set_node_enabled(s, true)
	)
	_cooldown_remaining = maxf(sabotage_cooldown, 0.25)


func _has_power_node(node: Node) -> bool:
	if node == null:
		return false
	if node.get("building_type") != null:
		return true
	return node.get("is_enabled") != null or node.get("can_accept_more_connections") != null


func _is_node_enabled(node: Node) -> bool:
	if node.get("is_enabled") != null:
		return node.is_enabled
	if node.get("building_type") != null:
		var entity = node.get("_ecs_entity") if node.get("_ecs_entity") != null else (node if node.has_method("get_component") else null)
		if entity and entity.has_method("get_component"):
			var c_node = entity.get_component(C_PowerNode)
			return c_node.is_enabled if c_node else true
	return true


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
