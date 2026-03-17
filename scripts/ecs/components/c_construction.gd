class_name C_Construction
extends Component
## Marker component for structures under construction.
## Present while building; removed when complete. Systems use with_none([C_Construction])
## to process only built structures (mining, targeting, monolith charge).

@export var is_built: bool = false
@export var build_progress: float = 0.0
