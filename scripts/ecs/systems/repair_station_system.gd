extends System
class_name RepairStationSystem
## Spawns repair robots at a rate when under capacity. Each robot costs 2 minerals.
## Manages signal connections for the repair priority queue.

const C_RepairStationClass = preload("res://scripts/ecs/components/c_repair_station.gd")
const C_RepairRobotStateClass = preload("res://scripts/ecs/components/c_repair_robot_state.gd")
const C_HealBeamClass = preload("res://scripts/ecs/components/c_heal_beam.gd")
const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")
const ROBOT_SCENE_PATH: String = "res://scenes/ecs/e_repair_robot.tscn"

var _robot_scene: PackedScene
var _robots_parent: Node
var _build_connected: bool = false
var _active_stations: Array = []


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_RepairStation]).with_none([C_Construction, C_Destroyed])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	if _robot_scene == null:
		_robot_scene = load(ROBOT_SCENE_PATH) as PackedScene
	if _robots_parent == null or not is_instance_valid(_robots_parent):
		var root: Node = Engine.get_main_loop().root
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		var current: Node = tree.current_scene if tree else null
		if current:
			_robots_parent = current.get_node_or_null("RepairRobots")
		if _robots_parent == null:
			_robots_parent = root.get_node_or_null("Main/RepairRobots")
		if _robots_parent == null:
			_robots_parent = root.get_node_or_null("Projectiles")
		if _robots_parent == null:
			_robots_parent = root

	if not _build_connected:
		_build_connected = true
		BuildManager.build_completed.connect(_on_build_completed)

	_active_stations.clear()
	for entity in entities:
		_active_stations.append(entity)
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_station = entity.get_component(C_RepairStation) as C_RepairStation
	var c_upgrades = entity.get_component(C_UpgradesScript)
	if c_structure == null or c_station == null or c_structure.is_destroyed:
		return
	if c_upgrades and c_upgrades.is_upgrading:
		return

	var structure_node: Node3D = c_structure.structure_node
	if structure_node == null or not is_instance_valid(structure_node):
		return

	if not c_station.initial_spawned:
		c_station.initial_spawned = true
		_connect_existing_structures(c_station, structure_node)
		var count: int = c_station.robot_capacity - c_station.robots_active
		for i in range(count):
			_spawn_robot(structure_node, entity, c_station)
		return

	if c_station.robots_active >= c_station.robot_capacity:
		return

	c_station.robot_spawn_timer += delta
	if c_station.robot_spawn_timer < c_station.robot_spawn_interval:
		return

	if not GameState.consume_minerals(c_station.mineral_cost_per_robot):
		return

	c_station.robot_spawn_timer = 0.0
	_spawn_robot(structure_node, entity, c_station)


func _spawn_robot(structure_node: Node3D, station_entity: Entity, c_station) -> void:
	if _robot_scene == null or _robots_parent == null:
		return
	var robot: Node = _robot_scene.instantiate()
	if robot == null:
		return

	var slot: int = c_station.claim_slot()
	if slot < 0:
		return
	var dock_pos: Vector3 = _get_dock_position(structure_node, slot)

	_robots_parent.add_child(robot)

	if ECS and ECS.world:
		ECS.world.add_entity(robot, [], false)

	var body: CharacterBody3D = robot.get_node_or_null("RobotBody") as CharacterBody3D
	if body:
		body.global_position = dock_pos

	var c_transform: C_Transform3D = robot.get_component(C_Transform3D) as C_Transform3D
	if c_transform:
		c_transform.position = dock_pos
		if body:
			c_transform.rotation = body.rotation

	var c_state = robot.get_component(C_RepairRobotStateClass) as C_RepairRobotState
	if c_state:
		c_state.source_station = structure_node
		c_state.source_station_entity = station_entity
		c_state.recharge_duration = c_station.recharge_duration
		c_state.state = C_RepairRobotState.State.FLY_TO_STATION
		c_state.heals_remaining = c_state.heals_max
		c_state.dock_slot = slot

	var c_heal = robot.get_component(C_HealBeamClass) as C_HealBeam
	if c_heal:
		c_heal.heal_rate = c_station.heal_per_second

	var c_targeting: C_Targeting = robot.get_component(C_Targeting) as C_Targeting
	if c_targeting:
		c_targeting.target_position = dock_pos

	c_station.robots_active += 1


func _get_dock_position(structure_node: Node3D, slot: int) -> Vector3:
	var dock_name: String = "VisualRoot/DockPoint" + str(slot)
	var dock: Node3D = structure_node.get_node_or_null(dock_name) as Node3D
	if dock and dock.is_inside_tree():
		return dock.global_position
	return structure_node.global_position + Vector3.UP * 0.4


func _connect_existing_structures(c_station: C_RepairStation, station_node: Node3D) -> void:
	if ECS == null or ECS.world == null:
		return
	var station_pos: Vector3 = station_node.global_position
	var structure_entities = ECS.world.query.with_all([C_Structure, C_Health, C_Team]).execute()
	for ent in structure_entities:
		var c_team: C_Team = ent.get_component(C_Team) as C_Team
		if c_team == null or c_team.team != "player":
			continue
		var c_structure: C_Structure = ent.get_component(C_Structure) as C_Structure
		if c_structure == null or c_structure.is_destroyed:
			continue
		var struct_node: Node3D = c_structure.structure_node
		if struct_node == null or not is_instance_valid(struct_node):
			continue
		if station_pos.distance_to(struct_node.global_position) > c_station.attack_range:
			continue
		c_station.connect_structure(ent, struct_node)


func _on_build_completed(_building_type: String, _position: Vector3, building: Node) -> void:
	if building == null or not is_instance_valid(building) or not (building is Entity):
		return
	var entity: Entity = building as Entity
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_health: C_Health = entity.get_component(C_Health) as C_Health
	var c_team: C_Team = entity.get_component(C_Team) as C_Team
	if c_structure == null or c_health == null or c_team == null or c_team.team != "player":
		return
	var struct_node: Node3D = c_structure.structure_node
	if struct_node == null or not is_instance_valid(struct_node):
		return
	for station_entity in _active_stations:
		if not is_instance_valid(station_entity):
			continue
		var c_station_struct: C_Structure = station_entity.get_component(C_Structure) as C_Structure
		var c_station: C_RepairStation = station_entity.get_component(C_RepairStationClass) as C_RepairStation
		if c_station_struct == null or c_station == null or c_station_struct.is_destroyed:
			continue
		var station_node: Node3D = c_station_struct.structure_node
		if station_node == null or not is_instance_valid(station_node):
			continue
		if station_node.global_position.distance_to(struct_node.global_position) <= c_station.attack_range:
			c_station.connect_structure(entity, struct_node)
