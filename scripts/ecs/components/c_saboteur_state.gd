class_name C_SaboteurState
extends Component
## Saboteur state machine: MOVE_TO, POWERING_UP, BLOCKING, POWERING_DOWN.
## Entity connects to state_changed for visuals; SaboteurSystem drives transitions.


enum State { MOVE_TO, POWERING_UP, BLOCKING, POWERING_DOWN }

signal state_changed(new_state: State, progress: float)

var state: State = State.MOVE_TO
var state_progress: float = 0.0
var target_structure: Node3D = null
var hover_position: Vector3 = Vector3.ZERO
var target_line_start: Vector3 = Vector3.ZERO
var target_line_end: Vector3 = Vector3.ZERO
var parked_movement: C_SaboteurMovement = null  # Stored when removed for POWERING_UP/BLOCKING

@export var power_up_duration: float = 2.0
@export var power_down_duration: float = 1.5
## Distance to line midpoint/segment to consider "on line" and begin transform.
@export var arrival_range: float = 0.2
