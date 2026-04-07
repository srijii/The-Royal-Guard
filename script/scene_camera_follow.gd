extends Camera2D

@export var target_path: NodePath = NodePath("../player")
@export var tilemap_path: NodePath = NodePath("../TileMap")
@export var follow_lerp_speed := 9.0
@export var scene_zoom := Vector2.ZERO

var _target: Node2D = null
var _tilemap: TileMap = null
var _has_bounds := false
var _bounds_min := Vector2.ZERO
var _bounds_max := Vector2.ZERO


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		var root = get_tree().get_current_scene()
		if root:
			_target = root.get_node_or_null("player") as Node2D

	_tilemap = get_node_or_null(tilemap_path) as TileMap
	if _tilemap == null:
		var root = get_tree().get_current_scene()
		if root:
			_tilemap = root.get_node_or_null("TileMap") as TileMap

	enabled = true
	if scene_zoom != Vector2.ZERO:
		zoom = scene_zoom
	else:
		scene_zoom = zoom

	if _target == null:
		push_warning("SceneCamera target not found, camera follow will stay where it is.")

	if _tilemap == null:
		push_warning("SceneCamera tilemap not found, camera bound clamping will be disabled.")
	else:
		_configure_limits(_tilemap)


func _process(delta: float) -> void:
	if _target == null:
		return

	var t := clampf(delta * follow_lerp_speed, 0.0, 1.0)
	var desired := global_position.lerp(_target.global_position, t)
	global_position = _clamp_to_bounds(desired)


func _fit_zoom_to_bounds() -> void:
	if not _has_bounds:
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return

	var bounds_size := _bounds_max - _bounds_min
	if bounds_size.x <= 1.0 or bounds_size.y <= 1.0:
		return

	var max_zoom_x := bounds_size.x / viewport_size.x
	var max_zoom_y := bounds_size.y / viewport_size.y
	var max_zoom := maxf(0.05, minf(max_zoom_x, max_zoom_y))

	if zoom.x > max_zoom or zoom.y > max_zoom:
		zoom = Vector2(max_zoom, max_zoom)


func _clamp_to_bounds(pos: Vector2) -> Vector2:
	if not _has_bounds:
		return pos

	var viewport_size := get_viewport_rect().size
	var half := Vector2(
		viewport_size.x * 0.5 * absf(zoom.x),
		viewport_size.y * 0.5 * absf(zoom.y)
	)

	var min_x := _bounds_min.x + half.x
	var max_x := _bounds_max.x - half.x
	var min_y := _bounds_min.y + half.y
	var max_y := _bounds_max.y - half.y

	if min_x > max_x:
		pos.x = (_bounds_min.x + _bounds_max.x) * 0.5
	else:
		pos.x = clampf(pos.x, min_x, max_x)

	if min_y > max_y:
		pos.y = (_bounds_min.y + _bounds_max.y) * 0.5
	else:
		pos.y = clampf(pos.y, min_y, max_y)

	return pos


func _configure_limits(tilemap: TileMap) -> void:
	var used_rect: Rect2i = tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return

	var tile_size := Vector2i(16, 16)
	if tilemap.tile_set:
		tile_size = tilemap.tile_set.tile_size

	var top_left_local := Vector2(
		used_rect.position.x * tile_size.x,
		used_rect.position.y * tile_size.y
	)
	var bottom_right_local := Vector2(
		(used_rect.position.x + used_rect.size.x) * tile_size.x,
		(used_rect.position.y + used_rect.size.y) * tile_size.y
	)

	var top_left_world := tilemap.to_global(top_left_local)
	var bottom_right_world := tilemap.to_global(bottom_right_local)

	_bounds_min = top_left_world
	_bounds_max = bottom_right_world
	_has_bounds = true

	limit_enabled = true
	limit_left = int(round(top_left_world.x))
	limit_top = int(round(top_left_world.y))
	limit_right = int(round(bottom_right_world.x))
	limit_bottom = int(round(bottom_right_world.y))
