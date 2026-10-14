extends Node
## Loads map dialogue (Dialogue Manager source strings) and shows the Cosmos balloon.

const MonolithTier = preload("res://scripts/game/monolith_dialogue_tier.gd")

const BALLOON_SCENE: String = "res://scenes/ui/cosmos_dialogue_balloon.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _dialogue_resource_from_source(source: String) -> Resource:
	var trimmed: String = source.strip_edges()
	if trimmed.is_empty():
		return null
	var compiler_cls: Variant = load("res://addons/dialogue_manager/compiler/compiler.gd")
	var result: Variant = compiler_cls.compile_string(trimmed, "map_inline")
	if result.errors.size() > 0:
		var dm_constants: Variant = load("res://addons/dialogue_manager/constants.gd")
		for err in result.errors:
			push_warning("Map dialogue compile line %d: %s" % [
				err.line_number + 1,
				dm_constants.get_error_message(err.error)
			])
		return null
	var dr_cls: Variant = load("res://addons/dialogue_manager/dialogue_resource.gd")
	var resource: Resource = dr_cls.new() as Resource
	resource.set("using_states", result.using_states)
	resource.set("labels", result.labels)
	resource.set("first_label", result.first_label)
	resource.set("character_names", result.character_names)
	resource.set("lines", result.lines)
	return resource


## Awaits until dialogue ends or fails. Returns true if dialogue was shown and completed.
func play_from_text(source: String, entry_label: String = "") -> bool:
	var resource: Resource = _dialogue_resource_from_source(source)
	if resource == null:
		return false
	var dm: Node = Engine.get_singleton("DialogueManager") as Node
	if dm == null:
		push_error("DialogueManager singleton missing; enable Dialogue Manager plugin and autoload.")
		return false
	# GDScript lambdas capture local variables by value. Use a mutable container
	# so the lambda's write is visible to the outer scope.
	# GDScript lambdas capture local variables by value. Use a mutable container
	# so the lambda's write is visible to the outer scope.
	var state: Array = [false]
	var on_ended := func(_res: Resource) -> void:
		state[0] = true
	var on_balloon_gone := func() -> void:
		state[0] = true
	dm.dialogue_ended.connect(on_ended, CONNECT_ONE_SHOT)
	var balloon: Node = dm.show_dialogue_balloon_scene(BALLOON_SCENE, resource, entry_label, []) as Node
	if balloon:
		balloon.tree_exited.connect(on_balloon_gone, CONNECT_ONE_SHOT)
	var safety: int = 0
	while not state[0]:
		await get_tree().process_frame
		safety += 1
		if safety > 60000:
			push_error("Map dialogue timed out waiting for dialogue to finish.")
			break
	if dm.dialogue_ended.is_connected(on_ended):
		dm.dialogue_ended.disconnect(on_ended)
	return true


func play_map_start_if_any(map_data: MapData, skip: bool) -> void:
	if skip or map_data == null:
		return
	var d: Dictionary = map_data.dialogue
	var start_text: String = String(d.get("start", ""))
	if start_text.is_empty():
		return
	GameState.set_session_state(GameState.SessionState.DIALOGUE_REALTIME)
	await play_from_text(start_text, "")
	if not GameState.is_game_over:
		GameState.set_session_state(GameState.SessionState.PLAYING)


func pick_end_victory_script(map_data: MapData) -> String:
	var d: Dictionary = map_data.dialogue
	var end_obj: Variant = d.get("end", {})
	if not end_obj is Dictionary:
		return ""
	var vic: Variant = (end_obj as Dictionary).get("victory", {})
	if not vic is Dictionary:
		return ""
	var tier: String = MonolithTier.compute_victory_tier(ECS.world if ECS else null)
	var script_text: String = String((vic as Dictionary).get(tier, ""))
	if script_text.is_empty():
		script_text = String((vic as Dictionary).get(MonolithTier.KEY_COMPLETE, ""))
	return script_text


func play_map_end_if_any(is_victory: bool) -> void:
	var map_data: MapData = MapLoader.current_map as MapData if MapLoader else null
	if map_data == null:
		return
	var d: Dictionary = map_data.dialogue
	if d.is_empty():
		return
	var text: String = ""
	if is_victory:
		text = pick_end_victory_script(map_data)
	else:
		var end_obj: Variant = d.get("end", {})
		if end_obj is Dictionary:
			text = String((end_obj as Dictionary).get("defeat", ""))
	if text.strip_edges().is_empty():
		return
	# Match is already WON/LOST (tree paused). Unpause so the world can animate during lines; restore after.
	var tree: SceneTree = get_tree()
	var was_paused: bool = tree.paused if tree else false
	if tree:
		tree.paused = false
	await play_from_text(text, "")
	if tree:
		tree.paused = was_paused
