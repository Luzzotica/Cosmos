extends ShipVisualHandler
class_name ReflectorVisualHandler
## Reflector visuals: center orb flash on attack_fired, subtle pulse.

const C_BeamWeaponClass = preload("res://scripts/ecs/components/c_beam_weapon.gd")

const ORB_BASE_EMISSION: float = 2.5
const ORB_PULSE_AMOUNT: float = 0.3
const ORB_PULSE_SPEED: float = 2.5
const ORB_FLASH_EMISSION: float = 6.0
const ORB_FLASH_DURATION: float = 0.08

@onready var _body: Node3D = get_parent() as Node3D
@onready var _center_orb: MeshInstance3D = _body.get_node_or_null("Body/CenterOrb") as MeshInstance3D

var _is_flashing: bool = false


func init(entity: Node) -> void:
	super.init(entity)
	var c_weapon = entity.get_component(C_BeamWeaponClass)
	if c_weapon and not c_weapon.attack_fired.is_connected(_on_attack_fired):
		c_weapon.attack_fired.connect(_on_attack_fired)


func _process(_delta: float) -> void:
	if _center_orb == null or _is_flashing:
		return
	var mat: StandardMaterial3D = _center_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		var pulse: float = ORB_PULSE_AMOUNT * sin(Time.get_ticks_msec() / 1000.0 * ORB_PULSE_SPEED)
		mat.emission_energy_multiplier = ORB_BASE_EMISSION + pulse


func _on_attack_fired(_from_pos: Vector3, _target_pos: Vector3, _beam_color: Color) -> void:
	if _body == null or _center_orb == null:
		return
	var mat: StandardMaterial3D = _center_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_enabled = true
		mat.emission_energy_multiplier = ORB_FLASH_EMISSION
		_is_flashing = true
		var timer: SceneTreeTimer = get_tree().create_timer(ORB_FLASH_DURATION)
		timer.timeout.connect(func() -> void:
			_is_flashing = false
			if not is_instance_valid(_center_orb):
				return
			var reset_mat: StandardMaterial3D = _center_orb.get_active_material(0) as StandardMaterial3D
			if reset_mat:
				reset_mat.emission_energy_multiplier = ORB_BASE_EMISSION
		)
