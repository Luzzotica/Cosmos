@tool
extends Node3D
class_name PowerUser
## Component that consumes power

signal power_consumed(amount: float)
signal power_state_changed(has_power: bool)
## Emitted when [member grid_draw_failed] changes (attempted grid draw with needed > 0 but drawn == 0).
signal grid_draw_failed_changed(failed: bool)

@export var use_power_cost: float = 5.0  # Power cost per use
@export var power_buffer_capacity: float = 15.0  # Internal buffer

@export_group("Out of power indicator")
@export var out_of_power_indicator_offset: Vector3 = Vector3(0.0, 4.2, 0.0)
@export var out_of_power_flash_half_period: float = 0.35  ## Seconds per fade half (full pulse = 2x)

var power_buffer: float = 0.0
var power_consumption: float = 0.0  # For tracking
var is_construction_user: bool = false  # True if this is a temporary construction power user

## True when the last grid draw attempt (needed > 0) received no power (drawn == 0).
var grid_draw_failed: bool = false

var _out_of_power_label: Label3D = null
var _out_of_power_flash_tween: Tween = null


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_register_with_power_graph")
		call_deferred("_setup_out_of_power_indicator")


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_unregister_from_power_graph()
	_stop_out_of_power_flash()


func _register_with_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.add_user(self)


func _unregister_from_power_graph() -> void:
	if PowerGraphManager:
		PowerGraphManager.remove_user(self)


func _setup_out_of_power_indicator() -> void:
	if Engine.is_editor_hint():
		return
	if _out_of_power_label != null:
		return
	_out_of_power_label = Label3D.new()
	_out_of_power_label.name = "OutOfPowerIndicator"
	_out_of_power_label.text = "⚡"
	_out_of_power_label.modulate = Color(1.0, 0.22, 0.18, 1.0)
	_out_of_power_label.font_size = 144
	_out_of_power_label.outline_size = 24
	_out_of_power_label.outline_modulate = Color(0.15, 0.0, 0.0, 0.9)
	_out_of_power_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_out_of_power_label.no_depth_test = true
	_out_of_power_label.position = out_of_power_indicator_offset
	_out_of_power_label.visible = false
	add_child(_out_of_power_label)
	_sync_indicator_process()
	_update_out_of_power_indicator()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or is_construction_user or use_power_cost <= 0.0:
		return
	if not grid_draw_failed:
		return
	_update_out_of_power_indicator()


## Check if user has enough power to operate
var has_power: bool:
	get:
		return power_buffer >= use_power_cost


## Try to consume power for one use
func consume_power() -> bool:
	if power_buffer >= use_power_cost:
		var was_powered: bool = has_power
		power_buffer -= use_power_cost
		power_consumption = use_power_cost
		power_consumed.emit(use_power_cost)
		if was_powered != has_power:
			power_state_changed.emit(has_power)
		# Try to refill buffer from grid
		draw_power_from_graph()
		
		return true
	else:
		# Not enough in buffer, try to draw from grid
		draw_power_from_graph()
		
		if power_buffer >= use_power_cost:
			var was_powered2: bool = has_power
			power_buffer -= use_power_cost
			power_consumption = use_power_cost
			power_consumed.emit(use_power_cost)
			if was_powered2 != has_power:
				power_state_changed.emit(has_power)
			return true
		
		return false


## Consume a specific amount from the buffer (e.g. per-shot cost). Mirrors [method consume_power].
func consume_power_amount(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if power_buffer >= amount:
		var was_powered: bool = has_power
		power_buffer -= amount
		power_consumption = amount
		power_consumed.emit(amount)
		if was_powered != has_power:
			power_state_changed.emit(has_power)
		draw_power_from_graph()
		return true
	draw_power_from_graph()
	if power_buffer >= amount:
		var was_powered2: bool = has_power
		power_buffer -= amount
		power_consumption = amount
		power_consumed.emit(amount)
		if was_powered2 != has_power:
			power_state_changed.emit(has_power)
		draw_power_from_graph()
		return true
	return false


## Draw power from the grid into the buffer
func draw_power_from_graph() -> void:
	if not PowerGraphManager:
		return
	
	var needed: float = power_buffer_capacity - power_buffer
	if needed <= 0:
		return
	
	var drawn: float = PowerGraphManager.draw_power_for_user(self, needed)
	var new_failed: bool = drawn <= 0.0
	if new_failed != grid_draw_failed:
		grid_draw_failed = new_failed
		grid_draw_failed_changed.emit(grid_draw_failed)
		_sync_indicator_process()
		_update_out_of_power_indicator()
	
	var old_has_power: bool = has_power
	power_buffer += drawn
	
	if old_has_power != has_power:
		power_state_changed.emit(has_power)


## Get buffer percentage (0.0 to 1.0)
func get_buffer_percentage() -> float:
	if power_buffer_capacity <= 0:
		return 0.0
	return power_buffer / power_buffer_capacity


## Manually add power to the buffer (for testing)
func add_power(amount: float) -> void:
	var old_has_power: bool = has_power
	power_buffer = minf(power_buffer + amount, power_buffer_capacity)
	if old_has_power != has_power:
		power_state_changed.emit(has_power)


func _get_structure_body() -> Node:
	var pn: Node = get_parent()
	if pn == null:
		return null
	return pn.get_parent()


func _is_structure_built() -> bool:
	var body: Node = _get_structure_body()
	if body == null:
		return true
	if body.has_method("is_built"):
		return body.is_built()
	return true


func _sync_indicator_process() -> void:
	var need: bool = (
		not Engine.is_editor_hint()
		and use_power_cost > 0.0
		and not is_construction_user
		and grid_draw_failed
	)
	set_process(need)


func _update_out_of_power_indicator() -> void:
	if _out_of_power_label == null:
		return
	var show: bool = (
		grid_draw_failed
		and use_power_cost > 0.0
		and not is_construction_user
		and _is_structure_built()
	)
	_out_of_power_label.position = out_of_power_indicator_offset
	_out_of_power_label.visible = show
	if show:
		if _out_of_power_flash_tween == null or not is_instance_valid(_out_of_power_flash_tween):
			_start_out_of_power_flash()
	else:
		_stop_out_of_power_flash()


func _start_out_of_power_flash() -> void:
	if _out_of_power_label == null:
		return
	_stop_out_of_power_flash()
	var half: float = maxf(out_of_power_flash_half_period, 0.05)
	_out_of_power_label.modulate.a = 1.0
	_out_of_power_flash_tween = create_tween()
	_out_of_power_flash_tween.set_loops()
	_out_of_power_flash_tween.set_trans(Tween.TRANS_SINE)
	_out_of_power_flash_tween.tween_property(_out_of_power_label, "modulate:a", 0.3, half)
	_out_of_power_flash_tween.tween_property(_out_of_power_label, "modulate:a", 1.0, half)


func _stop_out_of_power_flash() -> void:
	if _out_of_power_flash_tween != null and is_instance_valid(_out_of_power_flash_tween):
		_out_of_power_flash_tween.kill()
	_out_of_power_flash_tween = null
	if _out_of_power_label != null:
		_out_of_power_label.modulate.a = 1.0
