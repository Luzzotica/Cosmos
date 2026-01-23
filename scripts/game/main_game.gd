extends Node3D
## Main Game Scene Controller

@onready var structures_parent: Node3D = $Structures
@onready var asteroids_parent: Node3D = $Asteroids
@onready var enemies_parent: Node3D = $Enemies
@onready var camera: Camera3D = $RTSCamera

var _current_map_data: Resource = null
var _structure_count: int = 0


func _ready() -> void:
	# Load default map or wait for map to be specified
	_setup_default_game()


func _process(_delta: float) -> void:
	_check_game_over()


func _check_game_over() -> void:
	if GameState.is_game_over:
		return
	
	# Count remaining structures
	var count: int = 0
	for child in structures_parent.get_children():
		if child is BaseStructure and not child.is_destroyed:
			count += 1
	
	# If we had structures and now have none, game over
	if _structure_count > 0 and count == 0:
		GameState.trigger_game_over()
	
	_structure_count = count


func _setup_default_game() -> void:
	# Generate some asteroids for testing - more asteroids, closer to start
	_generate_asteroids(20)
	
	# Add a starter solar panel
	_add_starter_solar_panel()


func _generate_asteroids(count: int) -> void:
	var asteroid_scene: PackedScene = load("res://scenes/game/asteroid.tscn") as PackedScene
	if not asteroid_scene:
		push_warning("Asteroid scene not found")
		return
	
	for i in range(count):
		var asteroid: Node3D = asteroid_scene.instantiate() as Node3D
		if asteroid:
			# Distribute asteroids closer to the starting point
			# Generate in a ring around the center to avoid spawning on the starting panel
			var angle: float = randf() * TAU  # Random angle
			var distance: float = randf_range(15, 50)  # Between 15 and 50 units from center
			var x: float = cos(angle) * distance
			var z: float = sin(angle) * distance
			asteroid.global_position = Vector3(x, 0, z)
			asteroids_parent.add_child(asteroid)


func _add_starter_solar_panel() -> void:
	var solar_panel_scene: PackedScene = load("res://scenes/structures/solar_panel.tscn") as PackedScene
	if not solar_panel_scene:
		push_warning("Solar panel scene not found")
		return
	
	var solar_panel: Node3D = solar_panel_scene.instantiate() as Node3D
	if solar_panel:
		solar_panel.global_position = Vector3(0, 0, 0)
		# Must add to tree FIRST so _ready() runs and sets up components
		structures_parent.add_child(solar_panel)
		# Then mark as pre-built (skips build animation)
		if solar_panel.has_method("set_starter_panel"):
			solar_panel.set_starter_panel(true)


## Load a map from map data resource
func load_map(map_data: Resource) -> void:
	_current_map_data = map_data
	_clear_current_map()
	
	if map_data.has("asteroids"):
		for asteroid_data in map_data.asteroids:
			_spawn_asteroid_from_data(asteroid_data)
	
	if map_data.has("starting_structures"):
		for structure_data in map_data.starting_structures:
			_spawn_structure_from_data(structure_data)


func _clear_current_map() -> void:
	for child in asteroids_parent.get_children():
		child.queue_free()
	for child in structures_parent.get_children():
		child.queue_free()
	for child in enemies_parent.get_children():
		child.queue_free()


func _spawn_asteroid_from_data(data: Dictionary) -> void:
	var asteroid_scene: PackedScene = load("res://scenes/game/asteroid.tscn") as PackedScene
	if not asteroid_scene:
		return
	
	var asteroid: Node3D = asteroid_scene.instantiate() as Node3D
	if asteroid:
		asteroid.global_position = data.get("position", Vector3.ZERO)
		if data.has("size") and asteroid.has_method("set_size"):
			asteroid.set_size(data.size)
		if data.has("minerals") and asteroid.has_method("set_minerals"):
			asteroid.set_minerals(data.minerals)
		asteroids_parent.add_child(asteroid)


func _spawn_structure_from_data(data: Dictionary) -> void:
	var building_type: String = data.get("type", "")
	var building_data: Resource = BuildManager.get_building_data(building_type)
	if not building_data or not building_data.scene:
		return
	
	var structure: Node3D = building_data.scene.instantiate() as Node3D
	if structure:
		structure.global_position = data.get("position", Vector3.ZERO)
		# Must add to tree FIRST so _ready() runs and sets up components
		structures_parent.add_child(structure)
		# Then mark as pre-built if needed
		if data.get("pre_built", false) and structure.has_method("set_starter_panel"):
			structure.set_starter_panel(true)


## Get the structures parent node
func get_structures_parent() -> Node3D:
	return structures_parent


## Get the asteroids parent node  
func get_asteroids_parent() -> Node3D:
	return asteroids_parent


## Get the enemies parent node
func get_enemies_parent() -> Node3D:
	return enemies_parent
