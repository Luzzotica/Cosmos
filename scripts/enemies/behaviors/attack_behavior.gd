extends RefCounted
class_name EnemyAttackBehavior
## Handles cooldown and typed damage delivery.

const BeamPointResolverClass = preload("res://scripts/ecs/beam_point_resolver.gd")
const DamageEventClass: Script = preload("res://scripts/combat/damage_event.gd")

var damage_type: String = DamageEventClass.TYPE_PHYSICAL
var beam_color: Color = Color(1.0, 0.25, 0.2, 0.95)
var _cooldown_remaining: float = 0.0


func configure(profile: Dictionary) -> void:
	damage_type = String(profile.get("damage_type", damage_type))
	if profile.has("beam_color"):
		beam_color = profile["beam_color"]


func tick(delta: float) -> void:
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)


func try_attack(enemy: Node3D, target: Node3D, tactical_modifier: Dictionary) -> bool:
	if target == null or _cooldown_remaining > 0.0:
		return false
	var attack_range: float = float(enemy.get("attack_range"))
	var attack_range_multiplier: float = float(tactical_modifier.get("attack_range_multiplier", 1.0))
	if enemy.global_position.distance_to(target.global_position) > attack_range * attack_range_multiplier:
		return false

	var cooldown: float = float(enemy.get("attack_cooldown"))
	var cooldown_multiplier: float = float(tactical_modifier.get("attack_cooldown_multiplier", 1.0))
	_cooldown_remaining = maxf(cooldown * cooldown_multiplier, 0.1)

	if enemy.has_method("spawn_attack_beam"):
		enemy.spawn_attack_beam(BeamPointResolverClass.get_random_attack_point(target), beam_color)

	var damage: float = float(enemy.get("damage"))
	var damage_multiplier: float = float(tactical_modifier.get("damage_multiplier", 1.0))
	var packet: Dictionary = {
		"amount": damage * damage_multiplier,
		"damage_type": damage_type,
		"source": enemy,
		"tags": PackedStringArray()
	}
	if target.has_method("take_damage_event"):
		target.take_damage_event(packet)
	elif target.has_method("take_damage"):
		target.take_damage(float(packet.amount))
	return true
