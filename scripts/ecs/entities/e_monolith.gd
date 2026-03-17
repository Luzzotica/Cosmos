extends StructureEntity
class_name MonolithEntity
## ECS entity for monolith structure. Uses laser turret pattern with C_MonolithCharge.

var _pending_monolith_power_required: float = -1.0


func on_ready() -> void:
	super.on_ready()
	if _pending_monolith_power_required > 0:
		var c_charge: C_MonolithCharge = get_component(C_MonolithCharge) as C_MonolithCharge
		if c_charge:
			c_charge.power_required = _pending_monolith_power_required
		_pending_monolith_power_required = -1.0
