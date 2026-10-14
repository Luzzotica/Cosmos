extends Resource
class_name DialoguePortraitLibrary
## Maps dialogue character ids to emotion names -> Texture2D. Use with Cosmos dialogue balloon.

@export var portraits: Dictionary = {}
## Optional default character when line character is empty
@export var default_character_id: String = ""


func get_portrait_texture(character_id: String, emotion: String) -> Texture2D:
	var key: String = character_id.strip_edges().to_lower()
	if key.is_empty() and not default_character_id.is_empty():
		key = default_character_id.strip_edges().to_lower()
	if key.is_empty() or not portraits.has(key):
		return null
	var sub: Variant = portraits[key]
	if sub is Texture2D:
		return sub as Texture2D
	if sub is Dictionary:
		var d: Dictionary = sub as Dictionary
		if d.has(emotion):
			var t: Variant = d[emotion]
			if t is Texture2D:
				return t as Texture2D
		if d.has("neutral"):
			var n: Variant = d["neutral"]
			if n is Texture2D:
				return n as Texture2D
	return null
