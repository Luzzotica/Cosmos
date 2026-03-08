extends Node
class_name WaveController
## Optional node that enables wave-based combat. When present in the scene tree, GameState
## runs the wave timer and EnemyManager spawns waves. When absent (or disabled), no waves run.
## Use this for build-only / creative maps where players just want to build.

const GROUP_WAVE_CONTROLLER: String = "wave_controller"


func _ready() -> void:
	add_to_group(GROUP_WAVE_CONTROLLER)


func _exit_tree() -> void:
	remove_from_group(GROUP_WAVE_CONTROLLER)
