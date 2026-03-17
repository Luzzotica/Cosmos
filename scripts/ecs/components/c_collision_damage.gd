class_name C_CollisionDamage
extends Component
## ECS component for entities that deal collision damage on impact.
## Used by CollisionDamageSystem.

@export var amount: float = 20.0
@export var destroy_on_collision: bool = true
