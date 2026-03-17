class_name UpgradeNodeData
extends Resource
## Defines a single upgrade node within a skill tree. Holds cost, prerequisites,
## exclusions, and the stat modifications applied on purchase.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var mineral_cost: int = 100
@export var power_cost: float = 10.0
@export var upgrade_time: float = 3.0

@export var requires: Array[String] = []
@export var excludes: Array[String] = []

## Each entry: {"component": "C_BeamWeapon", "property": "attack_cooldown", "operation": "multiply", "value": 0.6}
## Operations: "add", "multiply", "set"
@export var stat_modifiers: Array[Dictionary] = []
