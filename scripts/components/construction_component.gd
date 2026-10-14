@tool
extends Node3D
class_name ConstructionComponent
## Component that handles structure construction progress.
## Creates a temporary PowerNode (skip_auto_connect) + PowerUser; shadow edges mirror the
## main PowerNode so power reaches construction without a second relay slot. Main stays disabled.

signal construction_progress_changed(progress: float)
signal construction_completed

@export var construction_time: float = 3.0
@export var requires_power: bool = true
@export var build_power_cost: float = 10.0

var build_progress: float = 0.0
var is_built: bool = false
var _power_paid: bool = false

var _power_node: Node3D = null  # Main PowerNode sibling (disabled during construction)
var _construction_power_node: PowerNode = null
var _construction_power_user: PowerUser = null
var _shadow_resync_timer: float = 0.0
const SHADOW_RESYNC_INTERVAL: float = 0.25
var on_construction_complete: Callable = Callable()

## Cached design max HP from health components (before construction mutates values).
var _design_max_cached: float = 0.0
## Previous construction cap for additive HP gains during active build (-1 = uninitialized).
var _construction_cap_prev: float = -1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	var parent: Node = get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling.has_method("can_accept_more_connections"):
				_power_node = sibling
				break
	
	if not is_built and requires_power:
		# Defer entire creation: parent is busy during _ready; also avoids crash when
		# parent may be freed/replaced during scene load (e.g. tutorial level).
		call_deferred("_create_construction_power_node")


func _create_construction_power_node() -> void:
	if is_built or not requires_power:
		return
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	_construction_power_user = PowerUser.new()
	_construction_power_user.use_power_cost = build_power_cost
	_construction_power_user.power_buffer_capacity = build_power_cost + 5.0
	_construction_power_user.is_construction_user = true

	if _power_node:
		_construction_power_node = PowerNode.new()
		_construction_power_node.skip_auto_connect_on_register = true
		_construction_power_node.max_connection_distance = _power_node.max_connection_distance if _power_node else PowerNode.CONNECTION_RANGE
		# Mirror main slot count so shadow can chain to peers + powered grid at once (main may have 2+ neighbors).
		var main_pn: PowerNode = _power_node as PowerNode
		_construction_power_node.max_connections = main_pn.max_connections if main_pn else 4
		_construction_power_node.is_enabled = true
		_construction_power_node.add_child(_construction_power_user)
		parent.add_child(_construction_power_node)
		if main_pn and not main_pn.connections_changed.is_connected(_on_main_power_connections_changed):
			main_pn.connections_changed.connect(_on_main_power_connections_changed)
		call_deferred("_try_construction_shadow_bridge")
	else:
		# Fallback: no sibling PowerNode — auto-connect only (cannot mirror main; may fail if relay full)
		_construction_power_node = PowerNode.new()
		_construction_power_node.max_connection_distance = PowerNode.CONNECTION_RANGE
		_construction_power_node.max_connections = 1
		_construction_power_node.is_enabled = true
		_construction_power_node.add_child(_construction_power_user)
		parent.add_child(_construction_power_node)


func _on_main_power_connections_changed() -> void:
	_try_construction_shadow_bridge()


func _try_construction_shadow_bridge() -> void:
	if is_built or not requires_power:
		return
	if not _power_node or not _construction_power_node:
		return
	if not _power_node is PowerNode or not _construction_power_node is PowerNode:
		return
	if PowerGraphManager:
		PowerGraphManager.sync_construction_shadow_edges(_power_node as PowerNode, _construction_power_node)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if is_built:
		return
	
	# Neighbor graphs change without our main's connections changing (e.g. peer links to solar).
	# Resync shadow edges so link targets stay on enabled nodes / neighbor construction shadows.
	if requires_power and _construction_power_node:
		_shadow_resync_timer += delta
		if _shadow_resync_timer >= SHADOW_RESYNC_INTERVAL:
			_shadow_resync_timer = 0.0
			_try_construction_shadow_bridge()
	
	var can_build: bool = _compute_can_build()
	
	if can_build:
		build_progress += delta / maxf(construction_time, 0.001)
		construction_progress_changed.emit(build_progress)
		
		if build_progress >= 1.0:
			_complete_construction()
			return
	
	_sync_construction_health(can_build)


func _compute_can_build() -> bool:
	if not requires_power:
		return true
	if _construction_power_node and _construction_power_node.get("connected_nodes"):
		var connected: Array = _construction_power_node.get("connected_nodes")
		if connected.size() > 0:
			if _power_paid:
				return true
			if _construction_power_user and _construction_power_user.consume_power():
				_power_paid = true
				return true
	return false


func _collect_health_targets() -> Array:
	var out: Array = []
	var host: Node = get_parent()
	if host == null:
		return out
	var hc: Node = host.get_node_or_null("HealthComponent")
	if hc is HealthComponent:
		out.append(hc)
	var entity: Node = host.get_parent()
	if entity and entity.has_method("get_component"):
		var ch: C_Health = entity.get_component(C_Health) as C_Health
		if ch:
			out.append(ch)
	var ecs_mirror: Node = host.get_node_or_null("ECSEntity")
	if ecs_mirror and ecs_mirror.has_method("get_component"):
		var ch2: C_Health = ecs_mirror.get_component(C_Health) as C_Health
		if ch2:
			var dup: bool = false
			for x in out:
				if x == ch2:
					dup = true
					break
			if not dup:
				out.append(ch2)
	return out


func _ensure_design_max_cached() -> void:
	if _design_max_cached > 0.0:
		return
	for t in _collect_health_targets():
		if t is HealthComponent:
			_design_max_cached = (t as HealthComponent).max_health
			return
		if t is C_Health:
			_design_max_cached = (t as C_Health).maximum
			return


func _apply_full_health_to_targets() -> void:
	_ensure_design_max_cached()
	var dm: float = _design_max_cached
	if dm <= 0.0:
		dm = 100.0
	_construction_cap_prev = -1.0
	for t in _collect_health_targets():
		if t is HealthComponent:
			var h: HealthComponent = t
			h.max_health = dm
			h.health = dm
		elif t is C_Health:
			var c: C_Health = t
			c.maximum = dm
			c.current = dm
			c.health_changed.emit(c.current, c.maximum)


func _sync_construction_health(can_build: bool) -> void:
	_ensure_design_max_cached()
	var design_max: float = _design_max_cached
	if design_max <= 0.0:
		design_max = 100.0
	
	var targets: Array = _collect_health_targets()
	if targets.is_empty():
		return
	
	# Waiting for construction power: fragile 1 HP.
	if requires_power and not can_build:
		_construction_cap_prev = -1.0
		for t in targets:
			if t is HealthComponent:
				var hw: HealthComponent = t
				hw.max_health = 1.0
				hw.health = 1.0
			elif t is C_Health:
				var cw: C_Health = t
				cw.maximum = 1.0
				cw.current = 1.0
				cw.health_changed.emit(cw.current, cw.maximum)
		return
	
	# Active construction: rising cap; additive HP per frame (damage between frames is preserved).
	var p: float = clampf(build_progress, 0.0, 1.0)
	var cap: float = 1.0 + (design_max - 1.0) * p
	if _construction_cap_prev < 0.0:
		_construction_cap_prev = 1.0
	var delta_cap: float = cap - _construction_cap_prev
	for t in targets:
		if t is HealthComponent:
			var h: HealthComponent = t
			var cur_h: float = h.health
			h.max_health = cap
			h.health = minf(cur_h + delta_cap, cap)
		elif t is C_Health:
			var c: C_Health = t
			var cur_c: float = c.current
			c.maximum = cap
			c.current = minf(cur_c + delta_cap, cap)
			c.health_changed.emit(c.current, c.maximum)
	_construction_cap_prev = cap


func _complete_construction() -> void:
	is_built = true
	build_progress = 1.0
	
	_apply_full_health_to_targets()
	
	_free_construction_power_node()
	
	if _power_node:
		_power_node.is_enabled = true
		if _power_node.has_method("invalidate_type_cache"):
			_power_node.invalidate_type_cache()
	
	construction_completed.emit()
	
	if on_construction_complete.is_valid():
		on_construction_complete.call()


## Set construction as already complete (for starter buildings)
func set_built() -> void:
	is_built = true
	build_progress = 1.0
	
	_apply_full_health_to_targets()
	
	_free_construction_power_node()
	
	if _power_node:
		_power_node.is_enabled = true
		if _power_node.has_method("invalidate_type_cache"):
			_power_node.invalidate_type_cache()


func _free_construction_power_node() -> void:
	if _power_node and _power_node is PowerNode:
		var main_pn: PowerNode = _power_node as PowerNode
		if main_pn.connections_changed.is_connected(_on_main_power_connections_changed):
			main_pn.connections_changed.disconnect(_on_main_power_connections_changed)
	if _construction_power_user and is_instance_valid(_construction_power_user):
		_construction_power_user.queue_free()
	_construction_power_user = null
	if _construction_power_node and is_instance_valid(_construction_power_node):
		_construction_power_node.queue_free()
	_construction_power_node = null


## Get construction progress (0.0 to 1.0)
func get_progress() -> float:
	return clampf(build_progress, 0.0, 1.0)
