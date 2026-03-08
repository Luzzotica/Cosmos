extends Panel
class_name WaveDesignerPanel
## Spreadsheet-style wave editor for map authoring.

signal applied(initial_delay: float, wave_interval: float, waves: Array)

const WaveDataClass: Script = preload("res://scripts/data/wave_data.gd")
const EnemyWaveEntryClass: Script = preload("res://scripts/data/enemy_wave_entry.gd")

static var _enemy_ids: PackedStringArray = PackedStringArray([
	"enemy_standard", "enemy_laser_immune", "enemy_physical_immune", "enemy_saboteur", "enemy_commander"
])

@onready var initial_delay: SpinBox = $Margin/VBox/GlobalRow/InitialDelay
@onready var wave_interval: SpinBox = $Margin/VBox/GlobalRow/WaveInterval
@onready var wave_table: VBoxContainer = $Margin/VBox/ScrollContainer/WaveTable
@onready var add_wave_button: Button = $Margin/VBox/ButtonRow/AddWaveButton
@onready var remove_wave_button: Button = $Margin/VBox/ButtonRow/RemoveWaveButton
@onready var apply_button: Button = $Margin/VBox/ButtonRow/ApplyButton
@onready var close_button: Button = $Margin/VBox/ButtonRow/CloseButton

var _waves: Array = []
var _wave_rows: Array = []
var _composition_popup: Window = null
var _editing_wave_index: int = -1


func _ready() -> void:
	add_wave_button.pressed.connect(_on_add_wave)
	remove_wave_button.pressed.connect(_on_remove_wave)
	apply_button.pressed.connect(_on_apply)
	close_button.pressed.connect(hide)


func configure(initial_delay_sec: float, interval_sec: float, waves: Array) -> void:
	initial_delay.value = initial_delay_sec
	wave_interval.value = interval_sec
	_waves.clear()
	for w in waves:
		_waves.append(w)
	_rebuild_wave_table()


func _rebuild_wave_table() -> void:
	# Clear rows (keep header)
	for i in range(wave_table.get_child_count() - 1, 0, -1):
		wave_table.get_child(i).queue_free()
	_wave_rows.clear()

	for i in range(_waves.size()):
		var wave: Resource = _waves[i]
		var row: HBoxContainer = _create_wave_row(i, wave)
		wave_table.add_child(row)
		_wave_rows.append(row)


func _create_wave_row(idx: int, wave: Resource) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var num_label: Label = Label.new()
	num_label.custom_minimum_size.x = 40
	num_label.text = str(idx + 1)
	row.add_child(num_label)

	var delay_sb: SpinBox = SpinBox.new()
	delay_sb.custom_minimum_size.x = 70
	delay_sb.min_value = 0.1
	delay_sb.max_value = 20.0
	delay_sb.step = 0.1
	delay_sb.value = wave.spawn_delay
	delay_sb.value_changed.connect(func(v: float) -> void: wave.spawn_delay = v)
	row.add_child(delay_sb)

	var count_sb: SpinBox = SpinBox.new()
	count_sb.custom_minimum_size.x = 60
	count_sb.min_value = 1
	count_sb.max_value = 200
	count_sb.step = 1
	count_sb.value = wave.enemy_count
	count_sb.value_changed.connect(func(v: float) -> void: wave.enemy_count = int(v))
	row.add_child(count_sb)

	var health_sb: SpinBox = SpinBox.new()
	health_sb.custom_minimum_size.x = 80
	health_sb.min_value = 0.1
	health_sb.max_value = 10.0
	health_sb.step = 0.1
	health_sb.value = wave.enemy_health_multiplier
	health_sb.value_changed.connect(func(v: float) -> void: wave.enemy_health_multiplier = v)
	row.add_child(health_sb)

	var speed_sb: SpinBox = SpinBox.new()
	speed_sb.custom_minimum_size.x = 80
	speed_sb.min_value = 0.1
	speed_sb.max_value = 3.0
	speed_sb.step = 0.05
	speed_sb.value = wave.enemy_speed_multiplier
	speed_sb.value_changed.connect(func(v: float) -> void: wave.enemy_speed_multiplier = v)
	row.add_child(speed_sb)

	var comp_btn: Button = Button.new()
	comp_btn.text = "Edit..."
	comp_btn.custom_minimum_size.x = 90
	comp_btn.pressed.connect(_on_composition_pressed.bind(idx))
	row.add_child(comp_btn)

	return row


func _on_composition_pressed(wave_idx: int) -> void:
	_editing_wave_index = wave_idx
	_open_composition_popup(_waves[wave_idx])


func _open_composition_popup(wave: Resource) -> void:
	if _composition_popup:
		_composition_popup.queue_free()
	_composition_popup = Window.new()
	_composition_popup.title = "Wave %d Composition" % (_editing_wave_index + 1)
	_composition_popup.unresizable = false
	_composition_popup.size = Vector2i(420, 320)
	_composition_popup.close_requested.connect(_on_composition_popup_closed)
	add_child(_composition_popup)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_composition_popup.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	vbox.add_child(scroll)
	var entries_container: VBoxContainer = VBoxContainer.new()
	scroll.add_child(entries_container)

	for entry in wave.enemy_composition:
		if entry:
			entries_container.add_child(_create_entry_row(entry, wave, entries_container))

	var add_btn: Button = Button.new()
	add_btn.text = "Add enemy type"
	add_btn.pressed.connect(func() -> void:
		var new_entry: Resource = EnemyWaveEntryClass.new()
		new_entry.enemy_id = "enemy_standard"
		new_entry.count = 1
		new_entry.spawn_weight = 1.0
		wave.enemy_composition.append(new_entry)
		entries_container.add_child(_create_entry_row(new_entry, wave, entries_container))
	)
	vbox.add_child(add_btn)

	var done_btn: Button = Button.new()
	done_btn.text = "Done"
	done_btn.pressed.connect(_on_composition_popup_closed)
	vbox.add_child(done_btn)

	_composition_popup.popup_centered()


func _create_entry_row(entry: Resource, wave: Resource, _container: VBoxContainer) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var opt: OptionButton = OptionButton.new()
	opt.custom_minimum_size.x = 140
	for eid in _enemy_ids:
		opt.add_item(eid.replace("_", " ").capitalize(), _enemy_ids.find(eid))
	var idx: int = _enemy_ids.find(entry.enemy_id)
	opt.selected = idx if idx >= 0 else 0
	opt.item_selected.connect(func(i: int) -> void: entry.enemy_id = _enemy_ids[i])
	row.add_child(opt)

	var count_sb: SpinBox = SpinBox.new()
	count_sb.custom_minimum_size.x = 60
	count_sb.min_value = 1
	count_sb.max_value = 100
	count_sb.value = entry.count
	count_sb.value_changed.connect(func(v: float) -> void: entry.count = int(v))
	row.add_child(count_sb)

	var weight_sb: SpinBox = SpinBox.new()
	weight_sb.custom_minimum_size.x = 70
	weight_sb.min_value = 0.0
	weight_sb.max_value = 10.0
	weight_sb.step = 0.1
	weight_sb.value = entry.spawn_weight
	weight_sb.value_changed.connect(func(v: float) -> void: entry.spawn_weight = v)
	row.add_child(weight_sb)

	var del_btn: Button = Button.new()
	del_btn.text = "X"
	del_btn.pressed.connect(func() -> void:
		wave.enemy_composition.erase(entry)
		row.queue_free()
	)
	row.add_child(del_btn)

	return row


func _on_composition_popup_closed() -> void:
	if _composition_popup:
		_composition_popup.queue_free()
		_composition_popup = null


func _on_add_wave() -> void:
	var w: Resource = WaveDataClass.new()
	w.wave_number = _waves.size()
	w.enemy_count = 3 + _waves.size() * 2
	w.spawn_delay = 1.8
	w.enemy_health_multiplier = 1.0 + _waves.size() * 0.2
	w.enemy_speed_multiplier = 1.0 + _waves.size() * 0.05
	_waves.append(w)
	_rebuild_wave_table()


func _on_remove_wave() -> void:
	if _waves.size() > 0:
		_waves.pop_back()
		_rebuild_wave_table()


func _on_apply() -> void:
	for entry in _waves:
		if entry.enemy_composition.size() > 0:
			entry.enemy_count = entry.get_total_enemy_count()
	applied.emit(initial_delay.value, wave_interval.value, _waves)
	hide()
