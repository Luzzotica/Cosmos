extends Node
## Batches structure visuals into MultiMeshes and supports per-structure power states.

const ROLE_BASE: String = "base"
const ROLE_ACCENT: String = "accent"
const STATE_ACTIVE: String = "active"
const STATE_OFF: String = "off"
const STATE_PULSE: String = "pulse"
const FAR_AWAY: Vector3 = Vector3(0.0, -10000.0, 0.0)

var _root: Node3D = null
var _pool_nodes: Dictionary = {}  # pool_key -> MultiMeshInstance3D
var _pool_data: Dictionary = {}  # pool_key -> {"multimesh": MultiMesh, "free_indices": Array[int]}
var _material_cache: Dictionary = {}  # material_key -> Material
var _structures: Dictionary = {}  # structure_id -> data


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []
	
	for structure_id in _structures.keys():
		var data: Dictionary = _structures[structure_id]
		var structure: Node3D = data.get("structure")
		if not is_instance_valid(structure):
			to_remove.append(structure_id)
			continue
		
		var pulse_until: float = float(data.get("pulse_until", 0.0))
		var pulse_active: bool = pulse_until > now_sec
		var powered: bool = bool(data.get("powered", true))
		var target_state: String = STATE_PULSE if pulse_active else (STATE_ACTIVE if powered else STATE_OFF)
		
		if data.get("state", STATE_ACTIVE) != target_state:
			_rebind_structure_state(structure_id, target_state)
		
		_update_structure_transforms(structure_id)
	
	for structure_id in to_remove:
		unregister_structure_by_id(structure_id)


func register_structure(structure: Node3D, mesh_instances: Array[MeshInstance3D], accent_mesh_names: Array[String]) -> void:
	if not is_instance_valid(structure):
		return
	
	_ensure_root(structure)
	var structure_id: int = structure.get_instance_id()
	if _structures.has(structure_id):
		unregister_structure_by_id(structure_id)
	
	var accent_lookup: Dictionary = {}
	for mesh_name in accent_mesh_names:
		accent_lookup[String(mesh_name)] = true
	
	var entry_list: Array[Dictionary] = []
	for mesh_instance in mesh_instances:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
			continue
		# Never batch helper visuals that are intentionally hidden at registration time.
		if not mesh_instance.visible:
			continue
		
		var role: String = ROLE_ACCENT if accent_lookup.has(mesh_instance.name) else ROLE_BASE
		var source_material: Material = mesh_instance.get_active_material(0)
		if source_material == null:
			source_material = mesh_instance.material_override
		
		var state: String = STATE_ACTIVE
		if role == ROLE_BASE:
			state = STATE_ACTIVE
		var pool_key: String = _pool_key(mesh_instance.mesh, source_material, role, state)
		var index: int = _alloc_in_pool(pool_key, mesh_instance.mesh, source_material, role, state)
		_set_pool_transform(pool_key, index, mesh_instance.global_transform)
		mesh_instance.visible = false
		
		entry_list.append({
			"mesh_instance": mesh_instance,
			"mesh": mesh_instance.mesh,
			"material": source_material,
			"role": role,
			"state": state,
			"pool_key": pool_key,
			"index": index
		})
	
	_structures[structure_id] = {
		"structure": structure,
		"entries": entry_list,
		"powered": true,
		"pulse_until": 0.0,
		"state": STATE_ACTIVE
	}


func unregister_structure(structure: Node3D) -> void:
	if not is_instance_valid(structure):
		return
	unregister_structure_by_id(structure.get_instance_id())


func unregister_structure_by_id(structure_id: int) -> void:
	if not _structures.has(structure_id):
		return
	
	var data: Dictionary = _structures[structure_id]
	var entries: Array = data.get("entries", [])
	for entry_var in entries:
		var entry: Dictionary = entry_var
		_free_pool_index(entry.get("pool_key", ""), int(entry.get("index", -1)))
		var source_mesh: MeshInstance3D = entry.get("mesh_instance")
		if is_instance_valid(source_mesh):
			source_mesh.visible = true
	
	_structures.erase(structure_id)


func set_structure_powered(structure: Node3D, is_powered: bool) -> void:
	if not is_instance_valid(structure):
		return
	var structure_id: int = structure.get_instance_id()
	if not _structures.has(structure_id):
		return
	var data: Dictionary = _structures[structure_id]
	data["powered"] = is_powered
	_structures[structure_id] = data


func pulse_structure(structure: Node3D, duration_sec: float = 0.15) -> void:
	if not is_instance_valid(structure):
		return
	var structure_id: int = structure.get_instance_id()
	if not _structures.has(structure_id):
		return
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	var data: Dictionary = _structures[structure_id]
	data["pulse_until"] = maxf(float(data.get("pulse_until", 0.0)), now_sec + duration_sec)
	_structures[structure_id] = data


func _rebind_structure_state(structure_id: int, target_state: String) -> void:
	if not _structures.has(structure_id):
		return
	var data: Dictionary = _structures[structure_id]
	var entries: Array = data.get("entries", [])
	
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var role: String = entry.get("role", ROLE_BASE)
		var desired_state: String = STATE_ACTIVE if role == ROLE_BASE else target_state
		var current_state: String = entry.get("state", STATE_ACTIVE)
		if current_state == desired_state:
			continue
		
		var mesh: Mesh = entry.get("mesh")
		var source_material: Material = entry.get("material")
		var old_pool_key: String = entry.get("pool_key", "")
		var old_index: int = int(entry.get("index", -1))
		var new_pool_key: String = _pool_key(mesh, source_material, role, desired_state)
		var new_index: int = _alloc_in_pool(new_pool_key, mesh, source_material, role, desired_state)
		
		var source_mesh: MeshInstance3D = entry.get("mesh_instance")
		if is_instance_valid(source_mesh):
			_set_pool_transform(new_pool_key, new_index, source_mesh.global_transform)
		else:
			_set_pool_transform(new_pool_key, new_index, Transform3D(Basis.IDENTITY, FAR_AWAY))
		
		_free_pool_index(old_pool_key, old_index)
		entry["pool_key"] = new_pool_key
		entry["index"] = new_index
		entry["state"] = desired_state
		entries[i] = entry
	
	data["entries"] = entries
	data["state"] = target_state
	_structures[structure_id] = data


func _update_structure_transforms(structure_id: int) -> void:
	if not _structures.has(structure_id):
		return
	var data: Dictionary = _structures[structure_id]
	var entries: Array = data.get("entries", [])
	
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var source_mesh: MeshInstance3D = entry.get("mesh_instance")
		if not is_instance_valid(source_mesh):
			continue
		var pool_key: String = entry.get("pool_key", "")
		var index: int = int(entry.get("index", -1))
		_set_pool_transform(pool_key, index, source_mesh.global_transform)


func _ensure_root(fallback_parent: Node) -> void:
	if _root and is_instance_valid(_root):
		return
	
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main and main is Node3D:
		_root = Node3D.new()
		_root.name = "StructureVisuals"
		(main as Node3D).add_child(_root)
		return
	
	_root = Node3D.new()
	_root.name = "StructureVisuals"
	if fallback_parent:
		fallback_parent.add_child(_root)


func _pool_key(mesh: Mesh, source_material: Material, role: String, state: String) -> String:
	var mesh_id: String = str(mesh.get_rid().get_id())
	var mat_id: String = "none"
	if source_material:
		mat_id = str(source_material.get_rid().get_id())
	return "%s_%s_%s_%s" % [mesh_id, mat_id, role, state]


func _alloc_in_pool(pool_key: String, mesh: Mesh, source_material: Material, role: String, state: String) -> int:
	_ensure_pool(pool_key, mesh, source_material, role, state)
	var pool: Dictionary = _pool_data[pool_key]
	var free_indices: Array = pool.get("free_indices", [])
	var mm: MultiMesh = pool.get("multimesh")
	
	var index: int = -1
	if free_indices.is_empty():
		index = mm.instance_count
		mm.instance_count = index + 1
	else:
		index = int(free_indices.pop_back())
	
	pool["free_indices"] = free_indices
	_pool_data[pool_key] = pool
	return index


func _free_pool_index(pool_key: String, index: int) -> void:
	if pool_key.is_empty() or index < 0 or not _pool_data.has(pool_key):
		return
	var pool: Dictionary = _pool_data[pool_key]
	var free_indices: Array = pool.get("free_indices", [])
	free_indices.append(index)
	pool["free_indices"] = free_indices
	_pool_data[pool_key] = pool
	_set_pool_transform(pool_key, index, Transform3D(Basis.IDENTITY, FAR_AWAY))


func _set_pool_transform(pool_key: String, index: int, world_transform: Transform3D) -> void:
	if not _pool_data.has(pool_key) or index < 0:
		return
	var pool: Dictionary = _pool_data[pool_key]
	var mm: MultiMesh = pool.get("multimesh")
	if mm == null or index >= mm.instance_count:
		return
	mm.set_instance_transform(index, world_transform)


func _ensure_pool(pool_key: String, mesh: Mesh, source_material: Material, role: String, state: String) -> void:
	if _pool_data.has(pool_key):
		return
	
	_ensure_root(self)
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "MM_" + pool_key
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 0
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = _get_state_material(source_material, role, state)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	_root.add_child(mmi)
	_pool_nodes[pool_key] = mmi
	_pool_data[pool_key] = {
		"multimesh": mm,
		"free_indices": []
	}


func _is_structure_accent_shader(shader_mat: ShaderMaterial) -> bool:
	var shader_res: Shader = shader_mat.shader
	if shader_res == null:
		return false
	var path_str: String = shader_res.resource_path
	return "structure_accent" in path_str

func _get_state_material(source_material: Material, role: String, state: String) -> Material:
	if source_material == null:
		return null

	var mat_id: int = source_material.get_rid().get_id()
	var key: String = "%d_%s_%s" % [mat_id, role, state]
	if _material_cache.has(key):
		return _material_cache[key]

	var src_shader: ShaderMaterial = source_material as ShaderMaterial
	if src_shader != null:
		var shader_out: ShaderMaterial = src_shader.duplicate() as ShaderMaterial
		if shader_out == null:
			_material_cache[key] = source_material
			return source_material
		if _is_structure_accent_shader(shader_out) and role == ROLE_ACCENT:
			if state == STATE_OFF:
				var base_col: Color = shader_out.get_shader_parameter("base_color")
				shader_out.set_shader_parameter("base_color", base_col.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75))
				shader_out.set_shader_parameter("emission_strength", 0.0)
			elif state == STATE_PULSE:
				var orig: float = shader_out.get_shader_parameter("emission_strength")
				shader_out.set_shader_parameter("emission_strength", maxf(orig * 2.2, 3.0))
		_material_cache[key] = shader_out
		return shader_out

	var src_standard: StandardMaterial3D = source_material as StandardMaterial3D
	if src_standard == null:
		_material_cache[key] = source_material
		return source_material

	var out_mat: StandardMaterial3D = src_standard.duplicate() as StandardMaterial3D
	if out_mat == null:
		_material_cache[key] = source_material
		return source_material

	if role == ROLE_ACCENT:
		if state == STATE_OFF:
			out_mat.albedo_color = out_mat.albedo_color.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75)
			out_mat.emission_enabled = false
			out_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
			out_mat.emission_energy_multiplier = 0.0
		elif state == STATE_PULSE:
			out_mat.emission_enabled = true
			if out_mat.emission == Color(0.0, 0.0, 0.0, 1.0):
				out_mat.emission = out_mat.albedo_color
			out_mat.emission_energy_multiplier = maxf(out_mat.emission_energy_multiplier * 2.2, 3.0)
		else:
			out_mat.emission_enabled = true
			if out_mat.emission == Color(0.0, 0.0, 0.0, 1.0):
				out_mat.emission = out_mat.albedo_color
			out_mat.emission_energy_multiplier = maxf(out_mat.emission_energy_multiplier, 1.1)

	_material_cache[key] = out_mat
	return out_mat
