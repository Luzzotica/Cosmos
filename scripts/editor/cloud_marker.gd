extends Node3D
class_name CloudMarker
## Editor-only node representing an asteroid cloud region. Holds AsteroidCloudPlacement data.

const AsteroidCloudPlacementClass: Script = preload("res://scripts/data/asteroid_cloud_placement.gd")

var cloud_data: Resource:
	set(value):
		cloud_data = value
		_update_visual()

func _ready() -> void:
	if cloud_data == null:
		cloud_data = AsteroidCloudPlacementClass.new()
		cloud_data.center = global_position
		cloud_data.radius = 35.0
		cloud_data.count = 8
		cloud_data.min_size = 2.0
		cloud_data.max_size = 4.0
		cloud_data.min_minerals = 25.0
		cloud_data.max_minerals = 60.0
		cloud_data.seed = randi()
	_update_visual()


func _process(_delta: float) -> void:
	if cloud_data:
		cloud_data.center = global_position


func _update_visual() -> void:
	if not cloud_data:
		return
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance and mesh_instance.mesh is CylinderMesh:
		var cylinder: CylinderMesh = (mesh_instance.mesh as CylinderMesh).duplicate()
		cylinder.top_radius = cloud_data.radius
		cylinder.bottom_radius = cloud_data.radius
		mesh_instance.mesh = cylinder
	var collision: CollisionShape3D = get_node_or_null("Area3D/CollisionShape3D")
	if collision and collision.shape is CylinderShape3D:
		var cyl: CylinderShape3D = (collision.shape as CylinderShape3D).duplicate()
		cyl.radius = cloud_data.radius
		collision.shape = cyl
