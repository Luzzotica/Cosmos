extends RefCounted
class_name MonolithDialogueTier
## Computes monolith_* dialogue keys from victory-relevant monolith charge ratios.

const C_MonolithChargeClass = preload("res://scripts/ecs/components/c_monolith_charge.gd")
const C_StructureClass = preload("res://scripts/ecs/components/c_structure.gd")
const C_VictoryMonolithClass = preload("res://scripts/ecs/components/c_victory_monolith.gd")

const KEY_100: String = "monolith_100"
const KEY_90: String = "monolith_90"
const KEY_COMPLETE: String = "monolith_complete"


static func victory_monolith_entities(world: Node) -> Array:
	if world == null or not world.get("query"):
		return []
	var q: Variant = world.query
	var all_m: Array = q.with_all([C_MonolithChargeClass, C_StructureClass]).execute()
	var any_marked: bool = false
	for ent in all_m:
		if ent is Entity and (ent as Entity).get_component(C_VictoryMonolithClass):
			any_marked = true
			break
	var out: Array = []
	for ent in all_m:
		if not ent is Entity:
			continue
		var e: Entity = ent as Entity
		var c_struct: C_Structure = e.get_component(C_StructureClass) as C_Structure
		if c_struct and c_struct.is_destroyed:
			continue
		if any_marked:
			if e.get_component(C_VictoryMonolithClass):
				out.append(e)
		else:
			out.append(e)
	return out


static func compute_victory_tier(world: Node) -> String:
	var ents: Array = victory_monolith_entities(world)
	if ents.is_empty():
		return KEY_COMPLETE
	var ratios: Array[float] = []
	for ent in ents:
		if not ent is Entity:
			continue
		var c: C_MonolithCharge = (ent as Entity).get_component(C_MonolithChargeClass) as C_MonolithCharge
		if c == null or c.power_required <= 0.0:
			continue
		ratios.append(c.current_charge / c.power_required)
	if ratios.is_empty():
		return KEY_COMPLETE
	var all_full: bool = true
	var all_90: bool = true
	for r in ratios:
		if r < 1.0:
			all_full = false
		if r < 0.9:
			all_90 = false
	if all_full:
		return KEY_100
	if all_90:
		return KEY_90
	return KEY_COMPLETE
