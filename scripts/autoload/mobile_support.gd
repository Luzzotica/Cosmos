extends Node
## MobileSupport - phones and tablets (touch screens) in landscape.
##
## Detects a touch-first device, scales the UI so it is readable and thumb-sized,
## reads the browser's safe-area insets, and lightens rendering on mobile GPUs.
## Desktop (mouse and keyboard) keeps the original behaviour: every helper here
## is a no-op unless `is_touch` is true.

signal layout_changed

## Base-resolution units (the project is laid out for 2560x1440) per CSS pixel we
## aim for on touch screens: 0.6 means an 80-unit button is 48 CSS px tall.
const TOUCH_UNITS_TO_CSS: float = 0.6
const BASE_HEIGHT: float = 1440.0
const MAX_CONTENT_SCALE: float = 2.6
## Minimum touch target height in base units (80 * 0.6 = 48 CSS px).
const TOUCH_MIN_BUTTON_HEIGHT: float = 80.0
## 3D render scale on touch screens (UI stays at full resolution).
const TOUCH_3D_SCALE: float = 0.75

var is_touch: bool = false
## Safe-area insets in viewport (canvas) units: left, top, right, bottom.
var safe_left: float = 0.0
var safe_top: float = 0.0
var safe_right: float = 0.0
var safe_bottom: float = 0.0
## True while two or more fingers are down (pinch); build placement ignores it.
var multi_touch_active: bool = false

var _css_size: Vector2 = Vector2.ZERO
var _safe_css: Vector4 = Vector4.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_touch = _detect_touch()
	if not is_touch:
		return
	get_tree().root.size_changed.connect(_apply_layout)
	_apply_layout()
	_apply_render_settings()
	# The address bar and rotation can change the safe area after load.
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_poll_browser_metrics)
	add_child(t)


func _detect_touch() -> bool:
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("(function(){try{return !!(window.matchMedia&&window.matchMedia('(pointer: coarse)').matches)}catch(e){return false}})()", true)
		if v is bool:
			return v
		return DisplayServer.is_touchscreen_available()
	return OS.has_feature("mobile")


## Convert CSS pixels to viewport (canvas) units.
func css_to_view(px: float) -> float:
	if not is_touch or _css_size.y <= 0.0:
		return px
	return px * get_viewport().get_visible_rect().size.y / _css_size.y


func _read_css_metrics() -> void:
	if not OS.has_feature("web"):
		var ws: Vector2 = Vector2(DisplayServer.window_get_size())
		var sc: float = maxf(DisplayServer.screen_get_scale(), 1.0)
		_css_size = ws / sc
		_safe_css = Vector4.ZERO
		return
	var js: String = "(function(){var d=document.getElementById('cosmos-safe');if(!d){d=document.createElement('div');d.id='cosmos-safe';d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(d);}var s=getComputedStyle(d);return [window.innerWidth,window.innerHeight,parseFloat(s.paddingLeft)||0,parseFloat(s.paddingTop)||0,parseFloat(s.paddingRight)||0,parseFloat(s.paddingBottom)||0].join(',');})()"
	var v: Variant = JavaScriptBridge.eval(js, true)
	if not (v is String):
		return
	var parts: PackedStringArray = (v as String).split(",")
	if parts.size() < 6:
		return
	_css_size = Vector2(parts[0].to_float(), parts[1].to_float())
	_safe_css = Vector4(parts[2].to_float(), parts[3].to_float(), parts[4].to_float(), parts[5].to_float())


func _poll_browser_metrics() -> void:
	var old_size: Vector2 = _css_size
	var old_safe: Vector4 = _safe_css
	_read_css_metrics()
	if old_size != _css_size or old_safe != _safe_css:
		_apply_layout()


func _apply_layout() -> void:
	_read_css_metrics()
	var root: Window = get_tree().root
	if _css_size.x > 0.0 and _css_size.y > 0.0:
		# canvas_items + expand scales the 2560x1440 base by the smaller ratio
		# (height on phones, width on 4:3 tablets); boost it to TOUCH_UNITS_TO_CSS.
		var base: Vector2 = Vector2(root.content_scale_size)
		if base.x <= 0.0 or base.y <= 0.0:
			base = Vector2(BASE_HEIGHT * 16.0 / 9.0, BASE_HEIGHT)
		var stretch: float = minf(_css_size.x / base.x, _css_size.y / base.y)
		var factor: float = TOUCH_UNITS_TO_CSS / stretch
		root.content_scale_factor = clampf(factor, 1.0, MAX_CONTENT_SCALE)
	var k: float = css_to_view(1.0)
	safe_left = _safe_css.x * k
	safe_top = _safe_css.y * k
	safe_right = _safe_css.z * k
	safe_bottom = _safe_css.w * k
	layout_changed.emit()


func _apply_render_settings() -> void:
	var vp: Viewport = get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = TOUCH_3D_SCALE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.positional_shadow_atlas_size = 0
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	# Directional shadows are the most expensive pass on phone GPUs and barely
	# show at this top-down camera angle.
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = false


## Give every Button under `root` a thumb-sized minimum height (touch only).
## Also raises button text to at least `min_font` (base units, 30 = 18 CSS px).
func enlarge_buttons(root: Node, min_height: float = TOUCH_MIN_BUTTON_HEIGHT, min_font: int = 30) -> void:
	if not is_touch or root == null:
		return
	for b in root.find_children("*", "BaseButton", true, false):
		var c: Control = b as Control
		c.custom_minimum_size.y = maxf(c.custom_minimum_size.y, min_height)
		if c.get_theme_font_size("font_size") < min_font:
			c.add_theme_font_size_override("font_size", min_font)


## Scale a centered panel down (about its centre) so it fits the visible
## screen height inside the safe area. Touch only.
func fit_centered(panel: Control, margin: float = 16.0) -> void:
	if not is_touch or panel == null:
		return
	panel.scale = Vector2.ONE
	var avail: float = panel.get_viewport_rect().size.y - safe_top - safe_bottom - margin * 2.0
	var h: float = maxf(panel.size.y, panel.get_combined_minimum_size().y)
	var s: float = clampf(avail / h, 0.5, 1.0) if h > 0.0 else 1.0
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(s, s)


## True if a visible GUI control that stops mouse input is under `pos`
## (viewport units). Used to keep touches on buttons from reaching the world.
func is_point_over_ui(pos: Vector2) -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	# HUD controls live in CanvasLayers (or Controls) directly under the scene
	# root; skip the 3D world subtrees.
	for child in scene.get_children():
		if (child is CanvasLayer or child is Control) and _hit_ui(child, pos):
			return true
	return false


func _hit_ui(node: Node, pos: Vector2) -> bool:
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	if node is Control:
		var c: Control = node as Control
		if not c.is_visible_in_tree() or c.modulate.a < 0.05:
			return false
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(pos):
			return true
	elif not (node is CanvasLayer):
		return false
	for child in node.get_children():
		if _hit_ui(child, pos):
			return true
	return false
