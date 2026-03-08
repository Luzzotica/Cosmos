extends Observer
class_name PowerEdgeBlockedObserver
## Watches C_PowerEdge.is_blocked changes (e.g. enemy on power line). Updates edge enabled state.

func watch() -> Resource:
	return C_PowerEdge


func match() -> QueryBuilder:
	return q.with_all([C_PowerEdge])


func on_component_changed(edge_entity: Entity, _component: Resource, property: String, _new_value: Variant, _old_value: Variant) -> void:
	if property != "is_blocked":
		return
	if PowerGraph and edge_entity:
		PowerGraph.call_deferred("_deferred_edge_blocked_changed", edge_entity.get_instance_id())
