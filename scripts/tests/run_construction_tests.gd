extends Node
## Runs GUT with only the construction system tests.
## Use as main scene or run with "Run Current Scene" to test construction in-editor.

func _ready() -> void:
	var GutRunner = load("res://addons/gut/gui/GutRunner.tscn") as PackedScene
	var GutConfig = load("res://addons/gut/gut_config.gd") as GDScript

	var cfg = GutConfig.new()
	cfg.options.dirs = []
	cfg.options.tests = ["res://scripts/tests/test_construction_system.gd"]
	cfg.options.should_exit = true
	cfg.options.should_exit_on_success = false
	cfg.options.include_subdirs = false
	cfg.options.double_strategy = "partial"
	cfg.options.log_level = 1

	var runner = GutRunner.instantiate()
	runner.ran_from_editor = false
	runner.set_gut_config(cfg)
	add_child(runner)
	runner.run_tests()
