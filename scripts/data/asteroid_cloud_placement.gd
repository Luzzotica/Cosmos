@tool
extends Resource
class_name AsteroidCloudPlacement
## Data class for procedurally spawning asteroid clusters.

@export var center: Vector3 = Vector3.ZERO
@export var radius: float = 30.0
@export var count: int = 6
@export var min_size: float = 2.0
@export var max_size: float = 4.0
@export var min_minerals: float = 25.0
@export var max_minerals: float = 60.0
@export var seed: int = 0
