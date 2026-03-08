extends Observer
class_name PowerGraphObserver
## Watches C_PowerNode add/remove and is_enabled changes. Uses incremental graph updates.
## Per GECS OBSERVERS.md: use call_deferred to avoid timing issues during component mutation.

func watch() -> Resource:
	return C_PowerNode


func match() -> QueryBuilder:
	return q.with_all([C_Structure, C_PowerNode])


func on_component_added(entity: Entity, _component: Resource) -> void:
	if PowerGraph and entity:
		PowerGraph.call_deferred("_deferred_add_node", entity.get_instance_id())


func on_component_removed(entity: Entity, _component: Resource) -> void:
	if PowerGraph and entity:
		PowerGraph.call_deferred("_deferred_remove_node", entity.get_instance_id())


func on_component_changed(entity: Entity, _component: Resource, property: String, _new_value: Variant, _old_value: Variant) -> void:
	if property != "is_enabled":
		return
	if PowerGraph and entity:
		PowerGraph.call_deferred("_deferred_node_enabled_changed", entity.get_instance_id())
