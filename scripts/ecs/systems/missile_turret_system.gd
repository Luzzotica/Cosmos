extends System
class_name MissileTurretSystem
## Spawns missiles into storage at a rate, fires them sequentially when a target exists.

const C_MissileLauncherClass = preload("res://scripts/ecs/components/c_missile_launcher.gd")
const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")
const MissileBodyClass = preload("res://scripts/projectiles/missile_body.gd")
const MISSILE_SCENE_PATH: String = "res://scenes/projectiles/missile.tscn"

var _missile_scene: PackedScene
var _projectiles_parent: Node


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_MissileLauncherClass, C_Targeting]).with_none([C_Construction, C_Destroyed])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	if _missile_scene == null:
		_missile_scene = load(MISSILE_SCENE_PATH) as PackedScene
	if _projectiles_parent == null:
		var root: Node = Engine.get_main_loop().root
		_projectiles_parent = root.get_node_or_null("Projectiles")
		if _projectiles_parent == null:
			_projectiles_parent = root

	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_launcher = entity.get_component(C_MissileLauncherClass)
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_upgrades = entity.get_component(C_UpgradesScript)

	if c_structure == null or c_launcher == null or c_targeting == null or c_structure.is_destroyed:
		return
	if c_upgrades and c_upgrades.is_upgrading:
		return

	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return

	# 1. Spawn missiles into storage
	if c_launcher.missiles_stored < c_launcher.missile_capacity:
		c_launcher.spawn_timer += delta
		if c_launcher.spawn_timer >= c_launcher.missile_spawn_interval:
			c_launcher.spawn_timer = 0.0
			c_launcher.missiles_stored = mini(c_launcher.missiles_stored + 1, c_launcher.missile_capacity)
			c_launcher.missiles_stored_changed.emit(c_launcher.missiles_stored)

	# 2. Fire missiles when target exists and we have missiles
	var target: Node3D = c_targeting.target_node
	if target == null or not is_instance_valid(target):
		return
	if c_launcher.missiles_stored <= 0:
		return
	if structure_node.global_position.distance_to(target.global_position) > c_launcher.attack_range:
		return

	c_launcher.fire_cooldown_remaining -= delta
	if c_launcher.fire_cooldown_remaining > 0.0:
		return

	# Consume resources
	if not GameState.consume_minerals(c_launcher.mineral_cost_per_shot):
		return
	if structure_node.has_method("consume_power_for_missile") and not structure_node.consume_power_for_missile(c_launcher.power_cost_per_shot):
		GameState.add_minerals(c_launcher.mineral_cost_per_shot)
		return

	# Fire one missile from next slot (slot 0, then 1, etc.)
	var fire_slot: int = c_launcher.missile_capacity - c_launcher.missiles_stored
	var launch_pos: Vector3 = _get_launch_position(structure_node, fire_slot)

	_spawn_missile(launch_pos, target, c_launcher.damage, c_launcher.aoe_radius, c_launcher.damage_type, structure_node, c_launcher.attack_range)

	c_launcher.missiles_stored -= 1
	c_launcher.fire_cooldown_remaining = c_launcher.missile_fire_interval
	c_launcher.missile_fired.emit(launch_pos, target.global_position, fire_slot)
	c_launcher.missiles_stored_changed.emit(c_launcher.missiles_stored)


func _get_launch_position(structure_node: Node3D, slot_index: int = 0) -> Vector3:
	var vh: Node = structure_node.get_node_or_null("VisualHandler")
	if vh and vh.has_method("get_launch_position_for_slot"):
		return vh.call("get_launch_position_for_slot", slot_index)
	var launch_point: Node3D = structure_node.get_node_or_null("VisualRoot/LaunchPoint") as Node3D
	if launch_point and launch_point.is_inside_tree():
		return launch_point.global_position
	return structure_node.global_position + Vector3.UP * 0.6


func _spawn_missile(from_pos: Vector3, target: Node3D, damage: float, aoe_radius: float, damage_type: String, source: Node, attack_range: float = 45.0) -> void:
	if _missile_scene == null:
		return
	var missile: Node = _missile_scene.instantiate()
	if not missile or not (missile is MissileBodyClass):
		if missile:
			missile.queue_free()
		return

	var missile_body: Node = missile
	missile_body.setup(target, damage, aoe_radius, damage_type, source, attack_range)
	_projectiles_parent.add_child(missile)
	missile_body.global_position = from_pos
