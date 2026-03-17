extends Node3D
## Main Game Scene Controller

@onready var structures_parent: Node3D = $Structures
@onready var asteroids_parent: Node3D = $Asteroids
@onready var enemies_parent: Node3D = $Enemies
@onready var ecs_world: Node = $ECSWorld
@onready var camera: Camera3D = $RTSCamera
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var _current_map_data: Resource = null
var _structure_count: int = 0
var _sky_material: ShaderMaterial = null
var _aurora_material: ShaderMaterial = null
var _cursor_layer: CanvasLayer = null
var _cursor_sprite: TextureRect = null
var _cursor_textures: Dictionary = {}
var _cursor_hotspots: Dictionary = {}
var _cursor_state: int = 0
var _is_editor_mode: bool = false

const SKY_PARALLAX_SCALE: float = 0.00012
const AURORA_PARALLAX_SCALE: float = 0.0011
const CURSOR_TEXTURE_SIZE: int = 32
const CURSOR_LAYER_ORDER: int = 100
const DEFAULT_MAP_PATH: String = "res://resources/maps/tutorial_map.json"
const SESSION_MODE_EDITOR: int = 1
const StructureEntityScript = preload("res://scripts/ecs/entities/structure_entity.gd")

enum CursorState {
	NORMAL,
	HOVER,
	PAN_UP,
	PAN_DOWN,
	PAN_LEFT,
	PAN_RIGHT,
	HIDDEN
}


func _ready() -> void:
	# ECS must be set up before map load so Entity structures (mining station, laser turret)
	# get registered via MapLoader._spawn_structure -> ECS.world.add_entity.
	# World._ready has already run (children before parent in Godot).
	_setup_ecs()
	# Enable physics object picking for 3D mouse input events
	get_viewport().physics_object_picking = true
	_setup_space_cursor()
	GameState.pause_changed.connect(_on_pause_changed)

	_setup_dynamic_sky()
	
	# Route all startup map loads through the shared map pipeline.
	_setup_startup_map()


func _setup_startup_map() -> void:
	GameState.reset()
	_is_editor_mode = false
	var session: Node = get_node_or_null("/root/GameSession")
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")

	var selected_map_path: String = DEFAULT_MAP_PATH
	if session and int(session.get("launch_mode")) == SESSION_MODE_EDITOR:
		_is_editor_mode = true
		_configure_editor_mode()
		var editor_map_path: String = String(session.get("selected_editor_map_path"))
		if not editor_map_path.is_empty():
			selected_map_path = editor_map_path
	elif session and not String(session.get("selected_story_map_path")).is_empty():
		_configure_story_mode()
		selected_map_path = String(session.get("selected_story_map_path"))
	elif story_manager and story_manager.has_method("get_current_story_map_path"):
		_configure_story_mode()
		var story_map: String = story_manager.call("get_current_story_map_path")
		if not story_map.is_empty():
			selected_map_path = story_map
	else:
		_configure_story_mode()

	if ResourceLoader.exists(selected_map_path):
		MapLoader.load_map_from_json(selected_map_path, _is_editor_mode)
		_center_camera_on_spawn()
		if _is_editor_mode:
			_open_editor_panel_default()
		return

	push_warning("Startup map not found at '%s'; using procedural fallback." % selected_map_path)
	_setup_default_game()
	if _is_editor_mode:
		_open_editor_panel_default()


func _configure_editor_mode() -> void:
	var game_hud: Node = get_node_or_null("UI/GameHUD")
	if game_hud:
		game_hud.visible = false
		game_hud.set_process(false)
		game_hud.set_process_unhandled_input(false)
		game_hud.set_process_input(false)

	# Prevent combat systems while editing.
	if EnemyManager:
		EnemyManager.reset()
		EnemyManager.set_process(false)


func _open_editor_panel_default() -> void:
	var map_editor_scene: PackedScene = load("res://scenes/game/map_editor.tscn") as PackedScene
	if map_editor_scene:
		var map_editor: Node = map_editor_scene.instantiate()
		add_child(map_editor)
		if map_editor.has_method("set_editor_visible"):
			map_editor.call("set_editor_visible", true)


func _configure_story_mode() -> void:
	if EnemyManager:
		EnemyManager.set_process(true)


func _setup_ecs() -> void:
	if not ECS or not ecs_world or not ecs_world.get_script():
		return
	var world_script: Script = load("res://addons/gecs/ecs/world.gd") as Script
	if not world_script or ecs_world.get_script() != world_script:
		return
	ECS.world = ecs_world
	_add_ecs_enemy_systems()
	_register_existing_asteroid_entities()
	if ecs_world.has_method("finalize_system_setup"):
		ecs_world.finalize_system_setup()
	set_physics_process(true)


func _center_camera_on_spawn() -> void:
	if not camera:
		return
	if structures_parent.get_child_count() == 0:
		return
	var first_structure: Node = structures_parent.get_child(0)
	if first_structure and first_structure is Node3D and camera.has_method("set_camera_position"):
		camera.set_camera_position((first_structure as Node3D).global_position)


func _physics_process(delta: float) -> void:
	if ECS and ECS.world:
		ECS.process(delta)

func _process(_delta: float) -> void:
	if not _is_editor_mode:
		_check_win_conditions()
		_check_game_over()
	_update_sky_parallax()
	_update_cursor_visual()


func _unhandled_input(event: InputEvent) -> void:
	if _is_editor_mode:
		return
	if GameState.is_game_over:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			GameState.toggle_pause()
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _setup_dynamic_sky() -> void:
	if not world_environment or not world_environment.environment:
		return

	var sky: Sky = world_environment.environment.sky
	if not sky:
		return

	var sky_material: Material = sky.sky_material
	if sky_material is ShaderMaterial:
		_sky_material = sky_material as ShaderMaterial
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()

		_sky_material.set_shader_parameter("sky_seed", rng.randf_range(0.0, 10000.0))
		_sky_material.set_shader_parameter("galaxy_rotation", rng.randf_range(0.0, TAU))
		_sky_material.set_shader_parameter("galaxy_strength", rng.randf_range(0.16, 0.3))

		_update_sky_parallax()


func _update_sky_parallax() -> void:
	if not camera:
		return

	if _sky_material:
		var pos: Vector3 = camera.global_position
		_sky_material.set_shader_parameter("parallax_offset", Vector3(pos.x, 0.0, pos.z) * SKY_PARALLAX_SCALE)
		if camera.has_method("get_zoom_level"):
			var zoom: float = camera.get_zoom_level()
			var min_z: float = 15.0
			var max_z: float = 80.0
			var t: float = (zoom - min_z) / (max_z - min_z) if max_z > min_z else 0.0
			var zoom_scale: float = lerpf(1.0, 1.1, t)
			_sky_material.set_shader_parameter("star_zoom_scale", zoom_scale)


func _check_win_conditions() -> void:
	if GameState.is_game_over:
		return
	var map_data: MapData = MapLoader.current_map as MapData if MapLoader else null
	if map_data == null:
		return
	var win_mode: String = map_data.win_mode
	if win_mode == "none":
		return
	var win_minerals: int = map_data.win_minerals_mined
	var win_monolith: float = map_data.win_monolith_power_required

	var minerals_met: bool = (win_minerals <= 0) or (GameState.total_minerals_mined >= win_minerals)
	var monolith_met: bool = (win_monolith <= 0)
	if win_monolith > 0 and ECS and ECS.world:
		const C_MonolithChargeClass = preload("res://scripts/ecs/components/c_monolith_charge.gd")
		var monoliths: Array = ECS.world.query.with_all([C_MonolithChargeClass, C_Structure]).execute()
		for entity in monoliths:
			if entity is Entity:
				var c_charge = (entity as Entity).get_component(C_MonolithChargeClass)
				var c_structure: C_Structure = (entity as Entity).get_component(C_Structure) as C_Structure
				if c_charge and c_structure and not c_structure.is_destroyed and c_charge.current_charge >= c_charge.power_required:
					monolith_met = true
					break

	var victory: bool = false
	if win_mode == "minerals":
		victory = minerals_met
	elif win_mode == "monolith":
		victory = monolith_met
	elif win_mode == "both":
		victory = minerals_met and monolith_met

	if victory:
		GameState.trigger_victory()


func _check_game_over() -> void:
	if GameState.is_game_over:
		return
	
	# Count remaining structures
	var count: int = 0
	for child in structures_parent.get_children():
		if child is BaseStructure and not child.is_destroyed:
			count += 1
		elif is_instance_of(child, StructureEntityScript) and not child.is_destroyed():
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
	var asteroid_scene: PackedScene = load("res://scenes/ecs/e_asteroid.tscn") as PackedScene
	if not asteroid_scene:
		push_warning("Asteroid scene not found")
		return

	for i in range(count):
		var entity: Node = asteroid_scene.instantiate() as Node
		if entity:
			var angle: float = randf() * TAU
			var distance: float = randf_range(15, 50)
			var pos: Vector3 = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
			asteroids_parent.add_child(entity)
			var body: Node3D = entity.get_node_or_null("AsteroidBody") as Node3D
			if body:
				body.global_position = pos
			if ECS and ECS.world:
				ECS.world.add_entity(entity, [], false)


func _add_starter_solar_panel() -> void:
	var solar_panel_scene: PackedScene = load("res://scenes/ecs/e_solar_panel.tscn") as PackedScene
	if not solar_panel_scene:
		push_warning("Solar panel scene not found")
		return
	
	var solar_panel: Node = solar_panel_scene.instantiate()
	if solar_panel:
		structures_parent.add_child(solar_panel)
		var body: Node = solar_panel.get_node_or_null("StructureBody")
		if body and body is Node3D:
			(body as Node3D).global_position = Vector3(0, 0, 0)
			if camera and camera.has_method("set_camera_position"):
				camera.set_camera_position((body as Node3D).global_position)
		elif solar_panel is Node3D:
			(solar_panel as Node3D).global_position = Vector3(0, 0, 0)
			if camera and camera.has_method("set_camera_position"):
				camera.set_camera_position((solar_panel as Node3D).global_position)
		if ECS and ECS.world and solar_panel is Entity:
			ECS.world.add_entity(solar_panel as Entity, [], false)
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
		if ECS and ECS.world and child is Entity:
			ECS.world.remove_entity(child as Entity)
		else:
			child.queue_free()
	for child in structures_parent.get_children():
		child.queue_free()
	for child in enemies_parent.get_children():
		child.queue_free()


func _spawn_asteroid_from_data(data: Dictionary) -> void:
	var asteroid_scene: PackedScene = load("res://scenes/ecs/e_asteroid.tscn") as PackedScene
	if not asteroid_scene:
		return

	var entity: Node = asteroid_scene.instantiate() as Node
	if entity:
		asteroids_parent.add_child(entity)
		var body: Node3D = entity.get_node_or_null("AsteroidBody") as Node3D
		if body:
			body.global_position = data.get("position", Vector3.ZERO)
		if ECS and ECS.world:
			ECS.world.add_entity(entity, [], false)
		if entity.has_method("set_size") and data.has("size"):
			entity.call("set_size", data.size)
		if entity.has_method("set_minerals") and data.has("minerals"):
			entity.call("set_minerals", data.minerals)


func _spawn_structure_from_data(data: Dictionary) -> void:
	var building_type: String = data.get("type", "")
	var building_data: Resource = BuildManager.get_building_data(building_type)
	if not building_data or not building_data.scene:
		return
	
	var structure: Node3D = building_data.scene.instantiate() as Node3D
	if structure:
		# Must add to tree FIRST so _ready() runs and sets up components
		structures_parent.add_child(structure)
		structure.global_position = data.get("position", Vector3.ZERO)
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


func _setup_space_cursor() -> void:
	_cursor_textures = {
		CursorState.NORMAL: _build_normal_cursor_texture(),
		CursorState.HOVER: _build_hover_cursor_texture(),
		CursorState.PAN_UP: _build_arrow_cursor_texture(
			Vector2(16, 4), Vector2(8, 15), Vector2(24, 15), Rect2i(13, 15, 6, 12)
		),
		CursorState.PAN_DOWN: _build_arrow_cursor_texture(
			Vector2(16, 28), Vector2(8, 17), Vector2(24, 17), Rect2i(13, 5, 6, 12)
		),
		CursorState.PAN_LEFT: _build_arrow_cursor_texture(
			Vector2(4, 16), Vector2(15, 8), Vector2(15, 24), Rect2i(15, 13, 12, 6)
		),
		CursorState.PAN_RIGHT: _build_arrow_cursor_texture(
			Vector2(28, 16), Vector2(17, 8), Vector2(17, 24), Rect2i(5, 13, 12, 6)
		)
	}
	_cursor_hotspots = {
		CursorState.NORMAL: Vector2(6, 3),
		CursorState.HOVER: Vector2(16, 16),
		CursorState.PAN_UP: Vector2(16, 16),
		CursorState.PAN_DOWN: Vector2(16, 16),
		CursorState.PAN_LEFT: Vector2(16, 16),
		CursorState.PAN_RIGHT: Vector2(16, 16)
	}
	_cursor_state = CursorState.NORMAL

	if _cursor_layer == null:
		_cursor_layer = CanvasLayer.new()
		_cursor_layer.layer = CURSOR_LAYER_ORDER
		add_child(_cursor_layer)

	if _cursor_sprite == null:
		_cursor_sprite = TextureRect.new()
		_cursor_sprite.custom_minimum_size = Vector2(CURSOR_TEXTURE_SIZE, CURSOR_TEXTURE_SIZE)
		_cursor_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cursor_layer.add_child(_cursor_sprite)

	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_set_cursor_state(CursorState.NORMAL)


func _update_cursor_visual() -> void:
	if _cursor_sprite == null:
		return

	var next_state: int = CursorState.NORMAL
	if GameState.is_game_over:
		next_state = CursorState.NORMAL
	elif GameState.is_paused or BuildManager.is_in_build_mode:
		next_state = CursorState.HIDDEN
	else:
		var edge_pan_state: int = _get_edge_pan_cursor_state()
		if edge_pan_state != CursorState.NORMAL:
			next_state = edge_pan_state
		elif _is_hovering_selectable():
			next_state = CursorState.HOVER

	_set_cursor_state(next_state)
	if next_state != CursorState.HIDDEN:
		var hotspot: Vector2 = _get_cursor_hotspot(next_state)
		_cursor_sprite.position = get_viewport().get_mouse_position() - hotspot


func _get_edge_pan_cursor_state() -> int:
	if GameState.is_game_over or GameState.is_paused:
		return CursorState.NORMAL
	if camera == null:
		return CursorState.NORMAL

	var edge_enabled: Variant = camera.get("enable_edge_panning")
	if edge_enabled is bool and not edge_enabled:
		return CursorState.NORMAL

	var margin_value: Variant = camera.get("edge_pan_margin")
	var edge_margin: float = float(margin_value) if margin_value != null else 8.0
	if edge_margin <= 0.0:
		return CursorState.NORMAL

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return CursorState.NORMAL
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var screen_size: Vector2 = viewport.get_visible_rect().size

	var near_left: bool = mouse_pos.x < edge_margin
	var near_right: bool = mouse_pos.x > screen_size.x - edge_margin
	var near_up: bool = mouse_pos.y < edge_margin
	var near_down: bool = mouse_pos.y > screen_size.y - edge_margin

	var distances: Dictionary = {}
	if near_left:
		distances[CursorState.PAN_LEFT] = mouse_pos.x
	if near_right:
		distances[CursorState.PAN_RIGHT] = screen_size.x - mouse_pos.x
	if near_up:
		distances[CursorState.PAN_UP] = mouse_pos.y
	if near_down:
		distances[CursorState.PAN_DOWN] = screen_size.y - mouse_pos.y

	if distances.is_empty():
		return CursorState.NORMAL

	var best_state: int = CursorState.NORMAL
	var best_distance: float = INF
	for state in distances.keys():
		var distance_to_edge: float = float(distances[state])
		if distance_to_edge < best_distance:
			best_distance = distance_to_edge
			best_state = int(state)

	return best_state


func _set_cursor_state(new_state: int) -> void:
	if _cursor_sprite == null:
		return
	if _cursor_state == new_state and (new_state == CursorState.HIDDEN or _cursor_sprite.texture != null):
		_cursor_sprite.visible = new_state != CursorState.HIDDEN
		return

	_cursor_state = new_state
	if new_state == CursorState.HIDDEN:
		_cursor_sprite.visible = false
		return

	_cursor_sprite.visible = true
	_cursor_sprite.texture = _cursor_textures.get(new_state, null)


func _get_cursor_hotspot(state: int) -> Vector2:
	var hotspot: Variant = _cursor_hotspots.get(state, Vector2(16, 16))
	if hotspot is Vector2:
		return hotspot as Vector2
	return Vector2(16, 16)


func _is_hovering_selectable() -> bool:
	if GameState.is_game_over or GameState.is_paused:
		return false
	if BuildManager.is_hover_blocked():
		return false
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var collider: Node = _raycast_collider_at_mouse(viewport.get_mouse_position())
	return _resolve_selectable_from_node(collider) != null


func _raycast_collider_at_mouse(mouse_pos: Vector2) -> Node:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var camera_3d: Camera3D = viewport.get_camera_3d()
	if camera_3d == null:
		return null

	var from: Vector3 = camera_3d.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera_3d.project_ray_normal(mouse_pos) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result: Dictionary = camera_3d.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider: Variant = result.get("collider")
	if not (collider is Node):
		return null
	return collider as Node


func _resolve_selectable_from_node(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.name == "SelectableComponent" and current.has_method("set_selected"):
			return current
		current = current.get_parent()
	return null


func _build_normal_cursor_texture() -> ImageTexture:
	var image: Image = Image.create(CURSOR_TEXTURE_SIZE, CURSOR_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var primary: Color = Color(0.76, 0.93, 1.0, 1.0)
	var secondary: Color = Color(0.52, 0.76, 0.9, 1.0)
	var glow: Color = Color(0.35, 0.58, 0.74, 0.5)

	var a: Vector2 = Vector2(4, 3)
	var b: Vector2 = Vector2(7, 24)
	var c: Vector2 = Vector2(20, 14)

	for y in range(CURSOR_TEXTURE_SIZE):
		for x in range(CURSOR_TEXTURE_SIZE):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var pixel: Color = Color(0, 0, 0, 0)
			var in_triangle: bool = _point_in_triangle(p, a, b, c)
			var in_tail: bool = x >= 12 and x <= 18 and y >= 14 and y <= 25

			if in_triangle or in_tail:
				pixel = primary
				if x > 13:
					pixel = secondary
			elif _point_in_triangle(p, a + Vector2(-1, -1), b + Vector2(-1, 1), c + Vector2(1, 1)):
				pixel = glow

			image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(image)


func _build_hover_cursor_texture() -> ImageTexture:
	var image: Image = Image.create(CURSOR_TEXTURE_SIZE, CURSOR_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center: Vector2 = Vector2(float(CURSOR_TEXTURE_SIZE) / 2.0, float(CURSOR_TEXTURE_SIZE) / 2.0)
	var ring_outer: float = 9.0
	var ring_inner: float = 7.0
	var ring_color: Color = Color(0.95, 0.86, 0.55, 0.9)
	var glow_color: Color = Color(1.0, 0.88, 0.55, 0.24)
	var core_color: Color = Color(1.0, 0.96, 0.82, 0.95)

	for y in range(CURSOR_TEXTURE_SIZE):
		for x in range(CURSOR_TEXTURE_SIZE):
			var delta: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = delta.length()
			var pixel: Color = Color(0, 0, 0, 0)

			if dist > ring_outer and dist <= ring_outer + 2.0:
				pixel = glow_color

			if dist >= ring_inner and dist <= ring_outer:
				pixel = ring_color
			elif (dist >= ring_inner - 1.0 and dist < ring_inner) or (dist > ring_outer and dist <= ring_outer + 0.9):
				pixel = Color(0.03, 0.03, 0.04, 0.9)

			if absf(delta.x) <= 0.6 or absf(delta.y) <= 0.6:
				if dist <= 6.0:
					pixel = core_color
			elif (absf(delta.x) <= 1.3 or absf(delta.y) <= 1.3) and dist <= 6.4 and pixel.a < 0.01:
				pixel = Color(0.05, 0.05, 0.06, 0.85)

			if absf(absf(delta.x) - absf(delta.y)) <= 0.55 and dist <= 4.5:
				pixel = Color(1.0, 0.95, 0.78, 0.82)
			elif absf(absf(delta.x) - absf(delta.y)) <= 1.1 and dist <= 5.0 and pixel.a < 0.01:
				pixel = Color(0.05, 0.05, 0.06, 0.78)

			if dist <= 1.2:
				pixel = Color(1, 1, 1, 1)

			image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(image)


func _build_arrow_cursor_texture(tip: Vector2, left: Vector2, right: Vector2, tail_rect: Rect2i) -> ImageTexture:
	var image: Image = Image.create(CURSOR_TEXTURE_SIZE, CURSOR_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var fill_color: Color = Color(0.55, 0.92, 1.0, 1.0)
	var highlight_color: Color = Color(0.82, 0.98, 1.0, 1.0)
	var outline_color: Color = Color(0.03, 0.04, 0.06, 0.92)
	var glow_color: Color = Color(0.32, 0.6, 0.72, 0.35)

	for y in range(CURSOR_TEXTURE_SIZE):
		for x in range(CURSOR_TEXTURE_SIZE):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var pixel: Color = Color(0, 0, 0, 0)
			var in_head: bool = _point_in_triangle(p, tip, left, right)
			var in_tail: bool = x >= tail_rect.position.x and x < tail_rect.position.x + tail_rect.size.x and y >= tail_rect.position.y and y < tail_rect.position.y + tail_rect.size.y
			var in_fill: bool = in_head or in_tail

			var in_head_outline: bool = _point_in_triangle(p, tip + Vector2(0, -1), left + Vector2(-1, 1), right + Vector2(1, 1))
			var tail_outline: Rect2i = Rect2i(tail_rect.position.x - 1, tail_rect.position.y - 1, tail_rect.size.x + 2, tail_rect.size.y + 2)
			var in_tail_outline: bool = x >= tail_outline.position.x and x < tail_outline.position.x + tail_outline.size.x and y >= tail_outline.position.y and y < tail_outline.position.y + tail_outline.size.y
			var in_outline: bool = (in_head_outline or in_tail_outline) and not in_fill

			if in_fill:
				pixel = fill_color
				if (x + y) % 5 == 0:
					pixel = highlight_color
			elif in_outline:
				pixel = outline_color
			elif in_head_outline or in_tail_outline:
				pixel = glow_color

			image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(image)


func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var s1: float = _sign_2d(p, a, b)
	var s2: float = _sign_2d(p, b, c)
	var s3: float = _sign_2d(p, c, a)
	var has_neg: bool = (s1 < 0.0) or (s2 < 0.0) or (s3 < 0.0)
	var has_pos: bool = (s1 > 0.0) or (s2 > 0.0) or (s3 > 0.0)
	return not (has_neg and has_pos)


func _sign_2d(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _add_ecs_enemy_systems() -> void:
	if not ECS or not ECS.world:
		return
	var targeting: Script = load("res://scripts/ecs/systems/enemy_targeting_system.gd") as Script
	var saboteur: Script = load("res://scripts/ecs/systems/saboteur_system.gd") as Script
	var saboteur_movement: Script = load("res://scripts/ecs/systems/saboteur_movement_system.gd") as Script
	var movement: Script = load("res://scripts/ecs/systems/enemy_movement_system.gd") as Script
	var collision_damage: Script = load("res://scripts/ecs/systems/collision_damage_system.gd") as Script
	var attack: Script = load("res://scripts/ecs/systems/beam_weapon_system.gd") as Script
	var structure_targeting: Script = load("res://scripts/ecs/systems/structure_targeting_system.gd") as Script
	if targeting:
		ECS.world.add_system(targeting.new(), true)
	if saboteur:
		ECS.world.add_system(saboteur.new(), true)
	if saboteur_movement:
		ECS.world.add_system(saboteur_movement.new(), true)
	if movement:
		ECS.world.add_system(movement.new(), true)
	if collision_damage:
		ECS.world.add_system(collision_damage.new(), true)
	if attack:
		ECS.world.add_system(attack.new(), true)
	if structure_targeting:
		ECS.world.add_system(structure_targeting.new(), true)
	var mining: Script = load("res://scripts/ecs/systems/mining_system.gd") as Script
	if mining:
		ECS.world.add_system(mining.new(), true)
	var monolith_charge: Script = load("res://scripts/ecs/systems/monolith_charge_system.gd") as Script
	if monolith_charge:
		ECS.world.add_system(monolith_charge.new(), true)
	var upgrade: Script = load("res://scripts/ecs/systems/upgrade_system.gd") as Script
	if upgrade:
		ECS.world.add_system(upgrade.new(), true)


func _register_existing_asteroid_entities() -> void:
	if not ECS or not ECS.world:
		return
	for child in asteroids_parent.get_children():
		if child is Entity and not ECS.world.entities.has(child):
			ECS.world.add_entity(child, [], false)




func _on_pause_changed(paused: bool) -> void:
	if _cursor_sprite == null:
		return
	if paused:
		_cursor_sprite.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_update_cursor_visual()
