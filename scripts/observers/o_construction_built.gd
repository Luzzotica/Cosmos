extends Observer
class_name ConstructionBuiltObserver
## Watches C_Construction.is_built changes. Refreshes entity cache when structure becomes built.

func watch() -> Resource:
	return C_Construction


func match() -> QueryBuilder:
	return q.with_all([C_Construction])


func on_component_changed(entity: Entity, _component: Resource, property: String, _new_value: Variant, _old_value: Variant) -> void:
	if property != "is_built":
		return
	if PowerGraph and entity:
		PowerGraph.call_deferred("_deferred_refresh_entity_cache", entity.get_instance_id())
