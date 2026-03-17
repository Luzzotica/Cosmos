class_name UpgradeTreeData
extends Resource
## Defines a complete upgrade/skill tree for a structure type.
## Contains the tree identifier and all upgrade nodes within it.

const _UpgradeNodeData = preload("res://scripts/data/upgrade_node_data.gd")

@export var tree_id: String = ""
@export var nodes: Array[Resource] = []
