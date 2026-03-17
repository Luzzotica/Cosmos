extends Node
class_name ShipVisualHandler
## Base for ship-specific visual behavior handlers.
## Add as child of the ship CharacterBody3D. Entity calls body.initialize_visuals(entity);
## body calls handler.init(entity). Override init() to get components and wire signals.


func init(entity: Node) -> void:
	pass
