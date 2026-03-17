class_name C_Upgrades
extends Component
## Tracks per-entity upgrade state: which upgrades have been purchased,
## whether an upgrade is currently in progress, and the associated tree ID.

@export var upgrade_tree_id: String = ""
var purchased_upgrades: Array[String] = []
var is_upgrading: bool = false
var upgrade_progress: float = 0.0
var upgrade_power_paid: float = 0.0
var current_upgrade_id: String = ""
var _upgrade_visuals_started: bool = false
