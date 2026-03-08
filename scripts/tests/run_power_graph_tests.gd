extends Node
## Runs GUT with only the power graph tests.
## Use as main scene or run with "Run Current Scene" to test power graph in-editor.
## Also used by run_power_graph_tests.tscn.

func _ready() -> void:
	var GutRunner = load("res://addons/gut/gui/GutRunner.tscn") as PackedScene
	var GutConfig = load("res://addons/gut/gut_config.gd") as GDScript

	var cfg = GutConfig.new()
	# Run only power graph tests; no dirs to avoid running other suites
	cfg.options.dirs = []
	cfg.options.tests = ["res://scripts/tests/test_power_graph.gd"]
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
