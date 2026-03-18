class_name C_RepairStation
extends Component
## ECS data component for repair station stats and runtime state.
## RepairStationSystem drives robot spawning.
## Maintains a signal-driven priority queue of damaged structures in range.

@export var robot_capacity: int = 3
@export var heal_per_second: float = 8.0
@export var attack_range: float = 45.0
@export var robot_spawn_interval: float = 6.0
@export var mineral_cost_per_robot: int = 2
@export var recharge_duration: float = 3.0

var robot_spawn_timer: float = 0.0
var robots_active: int = 0
var initial_spawned: bool = false
var occupied_slots: Array[bool] = []

## Priority queue of damaged structures: [{ entity: Entity, node: Node3D, health_pct: float }]
## Sorted ascending by health_pct (most damaged first).
var repair_queue: Array = []

## Tracks connected structures by entity instance ID ->
## { entity: Entity, node: Node3D, health_callable: Callable, destroyed_callable: Callable }
var _connected_entities: Dictionary = {}


func claim_slot() -> int:
	for i in range(occupied_slots.size()):
		if not occupied_slots[i]:
			occupied_slots[i] = true
			return i
	if occupied_slots.size() < robot_capacity:
		occupied_slots.append(true)
		return occupied_slots.size() - 1
	return -1


func release_slot(slot: int) -> void:
	if slot >= 0 and slot < occupied_slots.size():
		occupied_slots[slot] = false


func connect_structure(entity: Entity, structure_node: Node3D) -> void:
	var eid: int = entity.get_instance_id()
	if _connected_entities.has(eid):
		return
	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	if c_health == null:
		return
	var health_cb: Callable = _on_structure_health_changed.bind(structure_node, entity)
	var destroyed_cb: Callable = _on_structure_destroyed.bind(entity)
	c_health.health_changed.connect(health_cb)
	if entity.has_signal("destroyed"):
		entity.destroyed.connect(destroyed_cb)
	_connected_entities[eid] = {
		"entity": entity,
		"node": structure_node,
		"health_callable": health_cb,
		"destroyed_callable": destroyed_cb,
	}
	if c_health.current < c_health.maximum:
		_upsert_queue(entity, structure_node, c_health.current / c_health.maximum)


func disconnect_structure(entity: Entity) -> void:
	var eid: int = entity.get_instance_id()
	if not _connected_entities.has(eid):
		return
	var info: Dictionary = _connected_entities[eid]
	if is_instance_valid(entity):
		var c_health: C_Health = entity.get_component(C_Health) as C_Health
		var health_cb: Callable = info.get("health_callable", Callable())
		if c_health and health_cb.is_valid() and c_health.health_changed.is_connected(health_cb):
			c_health.health_changed.disconnect(health_cb)
		var destroyed_cb: Callable = info.get("destroyed_callable", Callable())
		if entity.has_signal("destroyed") and destroyed_cb.is_valid() and entity.destroyed.is_connected(destroyed_cb):
			entity.destroyed.disconnect(destroyed_cb)
	_connected_entities.erase(eid)
	_remove_from_queue(entity)


func peek_assignment() -> Node3D:
	while repair_queue.size() > 0:
		var entry: Dictionary = repair_queue[0]
		var ent: Entity = entry.get("entity") as Entity
		var node: Node3D = entry.get("node") as Node3D
		if ent == null or not is_instance_valid(ent) or node == null or not is_instance_valid(node):
			repair_queue.remove_at(0)
			continue
		var c_health: C_Health = ent.get_component(C_Health) as C_Health
		if c_health == null or c_health.current >= c_health.maximum:
			repair_queue.remove_at(0)
			continue
		return node
	return null


func _on_structure_health_changed(current_hp: float, max_hp: float, structure_node: Node3D, entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	if max_hp <= 0.0 or current_hp >= max_hp:
		_remove_from_queue(entity)
		return
	_upsert_queue(entity, structure_node, current_hp / max_hp)


func _on_structure_destroyed(entity: Entity) -> void:
	disconnect_structure(entity)


func _upsert_queue(entity: Entity, structure_node: Node3D, health_pct: float) -> void:
	for i in range(repair_queue.size()):
		if repair_queue[i]["entity"] == entity:
			repair_queue[i]["health_pct"] = health_pct
			repair_queue[i]["node"] = structure_node
			repair_queue.sort_custom(_sort_by_health)
			return
	repair_queue.append({ "entity": entity, "node": structure_node, "health_pct": health_pct })
	repair_queue.sort_custom(_sort_by_health)


func _remove_from_queue(entity: Entity) -> void:
	for i in range(repair_queue.size() - 1, -1, -1):
		if repair_queue[i]["entity"] == entity:
			repair_queue.remove_at(i)


static func _sort_by_health(a: Dictionary, b: Dictionary) -> bool:
	return a["health_pct"] < b["health_pct"]
