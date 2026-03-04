extends RefCounted
class_name EnemyBlackboard
## Shared tactical modifiers for enemy coordination.

var _modifier_by_enemy_id: Dictionary = {}


func set_enemy_modifier(enemy: Node3D, modifier: Dictionary, duration: float) -> void:
	if enemy == null:
		return
	var expires_at: float = Time.get_ticks_msec() / 1000.0 + maxf(duration, 0.05)
	_modifier_by_enemy_id[enemy.get_instance_id()] = {
		"modifier": modifier,
		"expires_at": expires_at
	}


func get_enemy_modifier(enemy: Node3D) -> Dictionary:
	if enemy == null:
		return {}
	var key: int = enemy.get_instance_id()
	if not _modifier_by_enemy_id.has(key):
		return {}
	var entry: Dictionary = _modifier_by_enemy_id[key]
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	if now_sec >= float(entry.get("expires_at", 0.0)):
		_modifier_by_enemy_id.erase(key)
		return {}
	return entry.get("modifier", {})


func clear_enemy(enemy: Node3D) -> void:
	if enemy == null:
		return
	_modifier_by_enemy_id.erase(enemy.get_instance_id())


func clear_expired() -> void:
	if _modifier_by_enemy_id.is_empty():
		return
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	for enemy_id in _modifier_by_enemy_id.keys():
		var entry: Dictionary = _modifier_by_enemy_id[enemy_id]
		if now_sec >= float(entry.get("expires_at", 0.0)):
			_modifier_by_enemy_id.erase(enemy_id)
