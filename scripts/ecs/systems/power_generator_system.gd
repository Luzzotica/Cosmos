extends System
class_name PowerGeneratorSystem
## Ticks generators, stores power in C_PowerSource, handles excess distribution.

func query() -> QueryBuilder:
	return q.with_all([C_PowerGenerator, C_PowerSource]).with_none([C_Construction])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		var c_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
		var c_source: C_PowerSource = entity.get_component(C_PowerSource) as C_PowerSource
		if c_gen == null or c_source == null:
			continue		
		if not c_gen.is_active:
			c_gen.current_output = 0.0
			continue

		var produced: float = c_gen.power_output * delta
		c_gen.current_output = c_gen.power_output

		var space: float = c_source.max_storage - c_source.current_storage
		if space > 0:
			var to_store: float = minf(produced, space)
			c_source.current_storage += to_store
			produced -= to_store

		# Excess: distribute to other sources in subgraph via BFS
		if produced > 0:
			_handle_generator_excess(entity, produced)


func _handle_generator_excess(generator_entity: Entity, excess_power: float) -> void:
	if not PowerGraph or excess_power <= 0:
		return

	while excess_power > 0:
		var result: Dictionary = PowerGraph.find_nearest_source_entity(generator_entity, true)
		var source_entity: Entity = result.get("source_entity") as Entity
		if source_entity == null:
			break

		var c_src: C_PowerSource = source_entity.get_component(C_PowerSource) as C_PowerSource
		if c_src == null:
			break

		var space: float = c_src.max_storage - c_src.current_storage
		if space <= 0:
			break

		var to_store: float = minf(excess_power, space)
		c_src.current_storage += to_store
		excess_power -= to_store

		# Flash power lines along the distribution path
		PowerGraph.flash_edges_along_path(result.get("path", []))
