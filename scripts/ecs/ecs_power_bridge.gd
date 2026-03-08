extends Node
## Bridge between ECS power systems and PowerGraphManager / UI.
## PowerGraphSystem populates this; PowerGraphManager and GameHUD read from it.
## Holds graph and subgraph data keyed by structure_node for compatibility.

class_name ECSPowerBridge

## structure_node (Node3D) -> connected structure_nodes
var graph: Dictionary = {}
## structure_node -> edge data for visualization
var edges: Dictionary = {}
## Array of subgraph data
var subgraphs: Array = []
## structure_node -> subgraph index
var node_to_subgraph: Dictionary = {}
## Total power stats (cached from subgraphs)
var power_capacity: float = 0.0
var power_current: float = 0.0
var power_generation: float = 0.0
var power_consumption: float = 0.0

## Subgraph-like structure for ECS
class SubgraphData:
	var nodes: Array = []  # structure_nodes
	var source_entities: Array = []
	var user_entities: Array = []
	var generator_entities: Array = []
	var _power_capacity: float = 0.0
	var _power_current: float = 0.0
	var _power_generation: float = 0.0
	var _power_consumption: float = 0.0
