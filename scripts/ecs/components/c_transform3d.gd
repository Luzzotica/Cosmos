class_name C_Transform3D
extends Component
## ECS data component for 3D transform. Syncs with entity node position/rotation/scale.

@export var position: Vector3 = Vector3.ZERO
@export var rotation: Vector3 = Vector3.ZERO
@export var scale: Vector3 = Vector3.ONE

func _init(p_pos: Vector3 = Vector3.ZERO, p_rot: Vector3 = Vector3.ZERO, p_scale: Vector3 = Vector3.ONE) -> void:
	position = p_pos
	rotation = p_rot
	scale = p_scale
