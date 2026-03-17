extends Node3D
## Level preview for the main menu. Builds a simple level via MapLoader each time.
## Solar, power node, miner, turret, asteroid. Miner actively mines the asteroid.
## The sun (DirectionalLight3D) slowly rotates for visual interest.

const C_StructureClass = preload("res://scripts/ecs/components/c_structure.gd")
const MAIN_MENU_PREVIEW_MAP: String = "res://resources/maps/main_menu_preview.json"
const SUN_ROTATION_SPEED: float = 0.08  # Radians per second

@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var structures_parent: Node3D = $Structures
@onready var asteroids_parent: Node3D = $Asteroids
@onready var power_lines_parent: Node3D = $PowerLines
@onready var ecs_world: Node = $ECSWorld


func _ready() -> void:
	if GameWorld:
		GameWorld.set_world(sun_light, power_lines_parent)
	_setup_ecs()
	_build_preview_level()


func _setup_ecs() -> void:
	if not ECS or not ecs_world or not ecs_world.get_script():
		return
	var world_script: Script = load("res://addons/gecs/ecs/world.gd") as Script
	if not world_script or ecs_world.get_script() != world_script:
		return
	ECS.world = ecs_world
	if ecs_world.has_method("finalize_system_setup"):
		ecs_world.finalize_system_setup()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if ECS and ECS.world:
		ECS.process(delta)


func _process(delta: float) -> void:
	if sun_light:
		sun_light.rotate_y(SUN_ROTATION_SPEED * delta)


func _build_preview_level() -> void:
	_clear_preview()
	var map_data: MapData = MapData.load_from_json(MAIN_MENU_PREVIEW_MAP)
	if map_data:
		MapLoader.load_map_into_containers(map_data, structures_parent, asteroids_parent, false)
	else:
		_push_fallback_content()
	call_deferred("_point_solar_panels_at_sun")


func _clear_preview() -> void:
	for child in structures_parent.get_children().duplicate():
		child.free()
	for child in asteroids_parent.get_children().duplicate():
		child.free()


func _point_solar_panels_at_sun() -> void:
	var sun_path: NodePath = NodePath("../../DirectionalLight3D")
	for child in structures_parent.get_children():
		var building_type: Variant = child.get("building_type")
		if building_type == "solar_panel":
			child.set("sun_light_path", sun_path)
		elif child.has_method("get_component"):
			var c_structure = child.get_component(C_StructureClass)
			if c_structure and c_structure.get("building_type") == "solar_panel":
				var body: Node = child.get_node_or_null("StructureBody")
				var vh: Node = body.get_node_or_null("VisualHandler") if body else null
				if vh and vh.get("sun_light_path") != null:
					vh.set("sun_light_path", sun_path)


func _push_fallback_content() -> void:
	var scene: PackedScene = load("res://scenes/ecs/e_solar_panel.tscn") as PackedScene
	if scene:
		var structure: Node = scene.instantiate()
		structures_parent.add_child(structure)
		var body: Node = structure.get_node_or_null("StructureBody")
		if body and body is Node3D:
			(body as Node3D).global_position = Vector3.ZERO
			var vh: Node = body.get_node_or_null("VisualHandler")
			if vh and vh.get("sun_light_path") != null:
				vh.set("sun_light_path", NodePath("../../DirectionalLight3D"))
		if ECS and ECS.world and structure is Entity:
			ECS.world.add_entity(structure as Entity, [], false)
		if structure.has_method("set_starter_panel"):
			structure.set_starter_panel(true)
