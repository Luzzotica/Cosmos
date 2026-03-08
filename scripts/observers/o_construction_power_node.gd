extends Observer
class_name ConstructionPowerNodeObserver
## Watches C_ConstructionPowerNode add/remove. Uses incremental graph updates.
## On remove: if entity has C_PowerNode (construction complete), refresh cache; else remove node.
## Per GECS OBSERVERS.md: use call_deferred to avoid timing issues during component mutation.

const _C_ConstructionPowerNode = preload("res://scripts/ecs/components/c_construction_power_node.gd")

func watch() -> Resource:
	return _C_ConstructionPowerNode


func match() -> QueryBuilder:
	return q.with_all([C_Structure, _C_ConstructionPowerNode])


func on_component_added(entity: Entity, _component: Resource) -> void:
	if PowerGraph and entity:
		PowerGraph.call_deferred("_deferred_add_node", entity.get_instance_id())


func on_component_removed(entity: Entity, _component: Resource) -> void:
	if not PowerGraph or not entity:
		return
	# Construction complete: C_PowerNode exists with copied connections; refresh cache only.
	# Structure demolished while under construction: no C_PowerNode; remove from graph.
	var entity_id: int = entity.get_instance_id()
	if entity.get_component(C_PowerNode) != null:
		PowerGraph.call_deferred("_deferred_refresh_entity_cache", entity_id)
	else:
		PowerGraph.call_deferred("_deferred_remove_node", entity_id)
