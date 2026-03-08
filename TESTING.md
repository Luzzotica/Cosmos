# Running Tests

## Power graph tests (in-editor)

**Option 1: Run Current Scene (recommended)**

1. Open `res://scenes/run_power_graph_tests.tscn` in the Godot editor
2. Press **Run Current Scene** (play button dropdown → "Run Current Scene", or use the shortcut)
3. A GUT window opens and runs only the power graph tests; it closes automatically when done

**Option 2: GUT panel – Run at cursor**

1. Open `res://scripts/tests/test_power_graph.gd` in the script editor
2. Open the **GUT** tab in the bottom panel
3. Click the **Run Script** button (shows `test_power_graph.gd`) to run that test file

**Option 3: GUT panel – Run all**

1. Open the **GUT** tab
2. Click **Run All** to run all tests in `res://scripts/tests/` (includes power graph, map pipeline, selection, etc.)

## Power graph tests (command line)

```bash
cd Cosmos
# Run power graph tests scene (shows GUT GUI, then exits)
godot --path . res://scenes/run_power_graph_tests.tscn

# Run via GUT CLI (headless, exits when done)
# -gconfig= skips .gutconfig.json so only power graph tests run (not all tests)
godot --path . -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://scripts/tests/test_power_graph.gd -gexit
```

> **Note:** Use `-gtest`, not `-gfile`. The `-gtest` option takes a full path to the test script.

## All tests (command line)

```bash
cd Cosmos
godot --path . -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit
```
