extends System
class_name PowerEdgeVisualSystem
## Updates power line visuals: bright when flashing/powered, gray when disabled (e.g. during construction).

const C_PowerEdge = preload("res://scripts/ecs/components/c_power_edge.gd")

const ENABLED_EMISSION: Color = Color(0.15, 0.5, 0.95)
const ENABLED_ALBEDO: Color = Color(0.2, 0.45, 0.9, 0.85)
const ENABLED_ENERGY: float = 3.0
const DISABLED_EMISSION: Color = Color(0.9, 0.2, 0.2)
const DISABLED_ALBEDO: Color = Color(0.8, 0.15, 0.15, 0.8)
const DISABLED_ENERGY: float = 0.8

func query() -> QueryBuilder:
	return q.with_all([C_PowerEdge])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		var c_edge: C_PowerEdge = entity.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge == null:
			continue
		if c_edge.line_node and is_instance_valid(c_edge.line_node):
			var enabled: bool = PowerGraph.is_edge_enabled_entity_ids(c_edge.entity_id_a, c_edge.entity_id_b)
			if c_edge.is_flashing:
				_set_line_appearance(c_edge.line_node, true)
			else:
				_set_line_appearance(c_edge.line_node, enabled)
		c_edge.is_flashing = false


func _set_line_appearance(line_node: Node3D, enabled: bool) -> void:
	for child in line_node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
				if enabled:
					mat.albedo_color = ENABLED_ALBEDO
					mat.emission = ENABLED_EMISSION
					mat.emission_energy_multiplier = ENABLED_ENERGY
				else:
					mat.albedo_color = DISABLED_ALBEDO
					mat.emission = DISABLED_EMISSION
					mat.emission_energy_multiplier = DISABLED_ENERGY
