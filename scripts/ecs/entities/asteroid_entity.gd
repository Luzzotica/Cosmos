extends Entity
class_name AsteroidEntity
## ECS entity for asteroids. Root is Entity; child is AsteroidBody (Node3D) with mesh and collision.
## Exposes asteroid interface (mine_minerals, global_position, etc.) for mining stations and selection.

signal minerals_changed(remaining: float, total: float)
signal depleted
signal destroyed


func define_components() -> Array:
	return []


func on_ready() -> void:
	var body: Node3D = _find_asteroid_body()
	if body:
		var c_asteroid: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
		if c_asteroid:
			c_asteroid.body_node = body
		var c_transform: C_Transform3D = get_component(C_Transform3D) as C_Transform3D
		if c_transform:
			c_transform.position = body.global_position
			c_transform.rotation = body.rotation
		if body.has_method("set_entity_ref"):
			body.call("set_entity_ref", self)
		if body.has_method("_update_visuals"):
			body.call("_update_visuals")


## Position for external callers (entity root is Node, has no global_position)
var global_position: Vector3:
	get:
		var body: Node3D = _find_asteroid_body()
		return body.global_position if body else Vector3.ZERO


var asteroid_size: float:
	get:
		var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
		return c.size if c else 3.0
	set(v):
		set_size(v)


var total_minerals: float:
	get:
		var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
		return c.total_minerals if c else 0.0


var remaining_minerals: float:
	get:
		var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
		return c.remaining_minerals if c else 0.0


var is_depleted: bool:
	get:
		var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
		return c.is_depleted if c else true


func mine_minerals(amount: int) -> int:
	var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
	if c == null or c.is_depleted:
		return 0
	var actual: int = mini(amount, int(c.remaining_minerals))
	c.remaining_minerals -= actual
	minerals_changed.emit(c.remaining_minerals, c.total_minerals)
	if c.remaining_minerals <= 0:
		c.is_depleted = true
		depleted.emit()
		destroyed.emit()
	var body: Node3D = _find_asteroid_body()
	if body and body.has_method("_on_minerals_changed"):
		body.call("_on_minerals_changed")
	var sel: Node = body.get_node_or_null("SelectableComponent") if body else null
	if sel and sel.has_method("notify_details_changed"):
		sel.call("notify_details_changed")
	return actual


func take_damage_event(event_payload: Dictionary) -> float:
	var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
	if c == null or c.is_depleted:
		return 0.0
	var amount: float = float(event_payload.get("amount", 0.0))
	if amount <= 0.0:
		return 0.0
	var actual: float = minf(amount, c.remaining_minerals)
	c.remaining_minerals -= actual
	minerals_changed.emit(c.remaining_minerals, c.total_minerals)
	if c.remaining_minerals <= 0:
		c.is_depleted = true
		depleted.emit()
		destroyed.emit()
	var body: Node3D = _find_asteroid_body()
	if body and body.has_method("_on_minerals_changed"):
		body.call("_on_minerals_changed")
	var sel: Node = body.get_node_or_null("SelectableComponent") if body else null
	if sel and sel.has_method("notify_details_changed"):
		sel.call("notify_details_changed")
	return actual


func show_mining_impact() -> void:
	var body: Node3D = _find_asteroid_body()
	if body and body.has_method("show_mining_impact"):
		body.call("show_mining_impact")


func set_size(size_val: float) -> void:
	var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
	if c:
		c.size = clampf(size_val, C_Asteroid.MIN_SIZE, C_Asteroid.MAX_SIZE)
		c.total_minerals = c.size * C_Asteroid.MINERAL_DENSITY
		c.remaining_minerals = c.total_minerals
	var body: Node3D = _find_asteroid_body()
	if body and body.has_method("_on_size_changed"):
		body.call("_on_size_changed")


func set_minerals(minerals_val: float) -> void:
	var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
	if c:
		c.total_minerals = minerals_val
		c.remaining_minerals = minerals_val
	var body: Node3D = _find_asteroid_body()
	if body and body.has_method("_on_minerals_changed"):
		body.call("_on_minerals_changed")


func get_mineral_percentage() -> float:
	var c: C_Asteroid = get_component(C_Asteroid) as C_Asteroid
	if c == null or c.total_minerals <= 0:
		return 0.0
	return c.remaining_minerals / c.total_minerals


func get_selection_name() -> String:
	return "Asteroid"


func get_selection_details() -> Dictionary:
	return {
		"name": get_selection_name(),
		"category": "asteroid",
		"faction": "neutral",
		"size": asteroid_size,
		"is_depleted": is_depleted,
		"resource_current": remaining_minerals,
		"resource_max": total_minerals,
		"stats": [
			{"label": "Size", "value": "%.1f" % asteroid_size},
			{"label": "Status", "value": "Depleted" if is_depleted else "Mineable"}
		]
	}


func _find_asteroid_body() -> Node3D:
	var body: Node = get_node_or_null("AsteroidBody")
	if body is Node3D:
		return body as Node3D
	for child in get_children():
		if child is Node3D:
			return child as Node3D
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		destroyed.emit()
