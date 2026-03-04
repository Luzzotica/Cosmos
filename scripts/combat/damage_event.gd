extends RefCounted
class_name DamageEvent
## Runtime combat packet carrying typed damage metadata.

const TYPE_GENERIC: String = "generic"
const TYPE_LASER: String = "laser"
const TYPE_PHYSICAL: String = "physical"
const TYPE_EMP: String = "emp"

var amount: float = 0.0
var damage_type: String = TYPE_GENERIC
var source: Node = null
var tags: PackedStringArray = PackedStringArray()
