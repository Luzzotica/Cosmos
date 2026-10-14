extends DialogueManagerExampleBalloon
class_name CosmosDialogueBalloon
## Dialogue Manager balloon with optional 2D portrait slide-in and emotion tags `[#emotion=name]`.

const DEFAULT_LIBRARY: String = "res://resources/dialogue/default_portrait_library.tres"
const PORTRAIT_W: float = 260.0

@export var portrait_library: DialoguePortraitLibrary

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var portrait_anchor: Control = %PortraitAnchor

var _portrait_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if portrait_library == null and ResourceLoader.exists(DEFAULT_LIBRARY):
		portrait_library = load(DEFAULT_LIBRARY) as DialoguePortraitLibrary
	super._ready()
	if portrait_anchor:
		_set_portrait_x(_portrait_off_x())


func apply_dialogue_line() -> void:
	await _tween_portrait_for_line()
	await super.apply_dialogue_line()


func _portrait_off_x() -> float:
	return -PORTRAIT_W - 40.0


func _tween_portrait_for_line() -> void:
	if portrait_rect == null or portrait_anchor == null or portrait_library == null:
		return
	var line: DialogueLine = dialogue_line
	if line == null:
		return
	var emotion: String = line.get_tag_value("emotion")
	if emotion.is_empty():
		emotion = "neutral"
	var tex: Texture2D = portrait_library.get_portrait_texture(line.character, emotion)
	portrait_rect.texture = tex
	portrait_rect.visible = tex != null
	portrait_anchor.visible = tex != null
	if not portrait_anchor.visible:
		return
	if _portrait_tween and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_set_portrait_x(_portrait_off_x())
	_portrait_tween = create_tween()
	_portrait_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_portrait_tween.set_parallel(true)
	_portrait_tween.tween_property(portrait_anchor, "offset_left", 24.0, 0.28)
	_portrait_tween.tween_property(portrait_anchor, "offset_right", 24.0 + PORTRAIT_W, 0.28)
	await _portrait_tween.finished


func _set_portrait_x(left: float) -> void:
	if portrait_anchor == null:
		return
	portrait_anchor.offset_left = left
	portrait_anchor.offset_right = left + PORTRAIT_W
