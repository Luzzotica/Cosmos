extends Node3D
## Level preview for the main menu. Builds a simple level via MapLoader each time.
## Solar, power node, miner, turret, asteroid. Miner actively mines the asteroid.
## The sun (DirectionalLight3D) slowly rotates for visual interest.

const MAIN_MENU_PREVIEW_MAP: String = "res://resources/maps/main_menu_preview.json"
const SUN_ROTATION_SPEED: float = 0.08  # Radians per second

@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var structures_parent: Node3D = $Structures
@onready var asteroids_parent: Node3D = $Asteroids
@onready var power_lines_parent: Node3D = $PowerLines


func _ready() -> void:
	if GameWorld:
		GameWorld.set_world(sun_light, power_lines_parent)
	_build_preview_level()


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
	for child in structures_parent.get_children():
		if child.get("building_type") == "solar_panel":
			child.set("sun_light_path", NodePath("../../DirectionalLight3D"))


func _push_fallback_content() -> void:
	var placement: StructurePlacement = StructurePlacement.new()
	placement.building_type = "solar_panel"
	placement.position = Vector3.ZERO
	var scene: PackedScene = load("res://scenes/structures/solar_panel.tscn") as PackedScene
	if scene:
		var structure: Node3D = scene.instantiate()
		structure.set("sun_light_path", NodePath("../../DirectionalLight3D"))
		structures_parent.add_child(structure)
		structure.global_position = Vector3.ZERO
