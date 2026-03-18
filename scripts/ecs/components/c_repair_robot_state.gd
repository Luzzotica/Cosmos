class_name C_RepairRobotState
extends Component
## Repair robot state machine: HEALING, FLY_TO_STATION, DOCKED_RECHARGING.
## RepairRobotSystem drives transitions; docking only at station for recharge.

enum State { HEALING, FLY_TO_STATION, DOCKED_RECHARGING }

signal state_changed(new_state: State, progress: float)

var state: State = State.HEALING
var heals_remaining: int = 10
var heals_max: int = 10
var source_station: Node = null
var source_station_entity: Node = null
var target_structure: Node3D = null
var state_progress: float = 0.0
var parked_movement: Resource = null
var dock_slot: int = 0

@export var arrival_range: float = 0.1
@export var arrival_snap_epsilon: float = 0.1
@export var arrival_lerp_duration: float = 0.15
@export var recharge_duration: float = 1.0
