@tool
extends Resource
class_name BuildingData
## Data resource defining a building type's properties

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export_group("Scenes")
@export var scene: PackedScene
@export var preview_scene: PackedScene

@export_group("Cost & Construction")
@export var cost: int = 100
@export var construction_time: float = 1.0
@export var placement_sphere_radius: float = 1.2

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Power")
@export var power_radius: float = 100.0
@export var max_connections: int = 4
@export var use_power_cost: float = 0.0
@export var power_buffer_capacity: float = 0.0
@export var energy_production: float = 0.0
@export var max_energy_storage: float = 0.0

@export_group("Combat")
@export var action_range: float = 0.0
@export var damage: float = 0.0
@export var attack_speed: float = 0.0

@export_group("Mining")
@export var mining_interval: float = 0.0
@export var mine_amount: float = 0.0

@export_group("Targeting Visualization")
@export var show_asteroid_targeting: bool = false
@export var show_enemy_targeting: bool = false
