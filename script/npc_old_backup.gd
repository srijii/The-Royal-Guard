extends CharacterBody2D

@export var move_speed := 42.0
@export var queen_stair_bias := 40.0
@export var queen_stair_bias2 := 45.0
@export var arrive_distance := 10.0
@export var checkpoint_visit_chance := 0.45
@export var flower_visit_chance := 0.38
@export var wander_wait_range := Vector2(0.8, 1.8)
@export var checkpoint_pause_range := Vector2(2.0, 4.0)
@export var flower_pause_range := Vector2(1.0, 4.0)
@export var debug_show_path := true
@export var minimum_target_distance := 90.0
@export var preferred_target_distance := 260.0
@export var target_pick_attempts := 28
@export var max_view_distance := 450.0
@export var stuck_distance_threshold := 8.0
@export var stuck_time_seconds := 1.5
@export var collision_reroute_cooldown := Vector2(0.25, 0.55)
@export var use_navigation_pathfinding := true
@export var strict_polygon_only := true
@export var reroute_lock_seconds := 0.7
@export var escape_commit_seconds := 1.25
@export var rapid_reroute_cluster_radius := 28.0
@export var rapid_reroute_limit := 2
@export var curious_trigger_distance := 520.0
@export var curious_cooldown_range := Vector2(11.0, 15.0)
@export var curious_watch_distance_range := Vector2(26.0, 44.0)
@export var player_blocking_stop_duration := 0.5

var wander_area := Rect2(Vector2(-300, -220), Vector2(600, 440))
var checkpoints: Array[Vector2] = []
var flower_spots: Array[Vector2] = []
var wander_polygon: PackedVector2Array = PackedVector2Array()
var _wander_polygon_bounds := Rect2(Vector2.ZERO, Vector2.ONE)

var _state := "idle"
var _target_position := Vector2.ZERO
var _wait_timer := 0.0
var _last_dir := Vector2.DOWN
var _current_anim := ""
var _last_progress_position := Vector2.ZERO
var _stuck_timer := 0.0
var _path_points: Array[Vector2] = []
var _path_index := 0
var _reroute_lock_timer := 0.0
var _reroute_anchor := Vector2.ZERO
var _rapid_reroute_count := 0
var _tilemap: TileMap = null
var _curious_cooldown_timer := 0.0
var _current_flower_target := Vector2.ZERO
var _just_finished_looking_at_flower := false
var _try_curious_counter := 0
var _saved_wander_target := Vector2.ZERO
var _should_restart_cooldown_on_move := false

# Dialogue system
var _normal_dialogue_lines := [
	"Bodyguard, please clear my path.",
	"Bodyguard, I need to pass.",
	"Please move aside for me, bodyguard.",
	"Bodyguard, make way."
]
var _harsh_dialogue_lines := [
	"Bodyguard, move now. You are delaying your queen.",
	"Enough. Clear the path immediately.",
	"Stand aside at once, bodyguard.",
	"Do not block me again. Move."
]
var _dialogue_display_time := 2.5
var _dialogue_timer := 0.0
var _showing_dialogue := false
var _player_ref: Node2D = null
var _blocking_distance := 120.0
var _collision_avoidance_distance := 60.0
var _block_event_cooldown := 0.8
var _block_event_timer := 0.0
var _player_blocking_move_timer := 0.0

# Emotion system (0..100)
var _rage_value := 0.0
var _fear_value := 25.0

@export var harsh_rage_threshold := 70.0
@export var rage_gain_min := 9.0
@export var rage_gain_max := 18.0
@export var rage_decay_per_second := 1.2
@export var fear_near_distance := 120.0
@export var fear_far_distance := 360.0
@export var fear_near_drop_per_second := 24.0
@export var fear_far_gain_per_second := 16.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
var _dialogue_panel: PanelContainer = null
var _dialogue_label: Label = null
var _hud_layer: CanvasLayer = null
var _emotion_panel: PanelContainer = null
var _rage_bar: ProgressBar = null
var _fear_bar: ProgressBar = null
var _debug_label: Label = null


func _ready() -> void:
	# Princess NPC should not hijack the player's camera/light.
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.enabled = false

	var light := get_node_or_null("PointLight2D") as PointLight2D
	if light:
		light.visible = false

	# Get reference to player from parent scene
	_player_ref = get_parent().get_node_or_null("player") as Node2D
	_tilemap = get_parent().get_node_or_null("TileMap") as TileMap
	
	# Create dialogue panel with background box
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.position = Vector2(-72.0, -104.0)
	_dialogue_panel.size = Vector2(144, 34)
	_dialogue_panel.z_index = 100  # Ensure it appears above other layers
	_dialogue_panel.visible = false
	
	# Style the panel
	var panel_stylebox = StyleBoxFlat.new()
	panel_stylebox.bg_color = Color(0, 0, 0, 0.8)  # Dark semi-transparent background
	panel_stylebox.border_color = Color.WHITE
	panel_stylebox.border_width_left = 2
	panel_stylebox.border_width_top = 2
	panel_stylebox.border_width_right = 2
	panel_stylebox.border_width_bottom = 2
	panel_stylebox.corner_radius_top_left = 6
	panel_stylebox.corner_radius_top_right = 6
	panel_stylebox.corner_radius_bottom_right = 6
	panel_stylebox.corner_radius_bottom_left = 6
	_dialogue_panel.add_theme_stylebox_override("panel", panel_stylebox)
	
	# Create label inside panel
	_dialogue_label = Label.new()
	_dialogue_label.text = ""
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialogue_label.add_theme_font_size_override("font_size", 9)  # Small text
	_dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	_dialogue_label.custom_minimum_size = Vector2(136, 26)
	_dialogue_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dialogue_panel.add_child(_dialogue_label)
	
	add_child(_dialogue_panel)

	_create_emotion_ui()
	_update_emotion_ui()

	_last_progress_position = global_position
	_start_wander()


func configure_princess_behavior(
		area_rect: Rect2,
		checkpoint_positions: Array[Vector2],
		polygon_points: PackedVector2Array = PackedVector2Array(),
		flower_positions: Array[Vector2] = []) -> void:
	wander_area = area_rect
	wander_polygon = polygon_points
	if wander_polygon.size() >= 3:
		_wander_polygon_bounds = _compute_polygon_bounds(wander_polygon)

	checkpoints.clear()
	for p in checkpoint_positions:
		if _is_inside_wander_area(p):
			checkpoints.append(p)

	flower_spots.clear()
	for p in flower_positions:
		if _is_inside_wander_area(p):
			flower_spots.append(p)
	print("DEBUG: Configured %d flowers out of %d passed (wander area filter applied)" % [flower_spots.size(), flower_positions.size()])


func _physics_process(delta: float) -> void:
	if _block_event_timer > 0.0:
		_block_event_timer -= delta
	if _reroute_lock_timer > 0.0:
		_reroute_lock_timer -= delta
	if _curious_cooldown_timer > 0.0:
		_curious_cooldown_timer -= delta
	if _player_blocking_move_timer > 0.0:
		_player_blocking_move_timer -= delta

	# Natural cooldown so emotions are not permanently maxed.
	_rage_value = max(0.0, _rage_value - rage_decay_per_second * delta)
	_update_fear_from_proximity(delta)
	_update_emotion_ui()

	# Update dialogue fade-out
	if _showing_dialogue:
		_dialogue_timer -= delta
		if _dialogue_timer <= 0.0:
			_clear_dialogue()

	if _state != "curious":
		_try_enter_curious_mode()
	
	match _state:
		"moving":
			_move_to_target(delta)
		"curious":
			_move_to_target(delta)
		"idle":
			_wait_timer -= delta
			_update_animation(Vector2.ZERO)
			if _wait_timer <= 0.0:
				_start_wander()

	if debug_show_path:
		queue_redraw()


func _start_wander() -> void:
	_target_position = _pick_next_target_with_direction_change()
	_rebuild_path_to_target()

	_stuck_timer = 0.0
	_last_progress_position = global_position
	_just_finished_looking_at_flower = false
	_state = "moving"


func _move_to_target(_delta: float) -> void:
	if not _is_inside_wander_area(global_position):
		_target_position = _random_point_in_wander_area()
		_rebuild_path_to_target()
		_state = "moving"

	if _path_points.is_empty():
		_rebuild_path_to_target()

	var move_target := _get_current_path_target()
	var to_target := move_target - global_position
	var distance := to_target.length()

	if distance <= arrive_distance:
		if _advance_path_target():
			return

		velocity = Vector2.ZERO
		move_and_slide()

		if _state == "curious":
			_update_animation(Vector2.ZERO)
			var look_dir := (_current_flower_target - global_position).normalized()
			if look_dir != Vector2.ZERO:
				_last_dir = look_dir
			_wait_timer = randf_range(flower_pause_range.x, flower_pause_range.y)
			# Don't set cooldown yet - it will be set when she starts moving again
			print("DEBUG: Arrived at flower! Looking for %.1fs" % [_wait_timer])
			# Stay in curious state while looking at flower - will transition to moving when _wait_timer expires
			return

		# At a flower spot, queen pauses briefly (1..4s).
		if (not _just_finished_looking_at_flower) and flower_spots.size() > 0 and _is_close_to_any_flower(global_position):
			_update_animation(Vector2.ZERO)
			_wait_timer = randf_range(flower_pause_range.x, flower_pause_range.y)
		# At a checkpoint, princess pauses and looks toward another interesting point.
		elif checkpoints.size() > 0 and _is_close_to_any_checkpoint(global_position):
			var look_point := _pick_look_point()
			var look_dir := (look_point - global_position).normalized()
			if look_dir != Vector2.ZERO:
				_last_dir = look_dir
			_update_animation(Vector2.ZERO)
			_wait_timer = randf_range(checkpoint_pause_range.x, checkpoint_pause_range.y)
		else:
			_wait_timer = randf_range(wander_wait_range.x, wander_wait_range.y)

		_state = "idle"
		return

	# If in curious mode and still looking at the flower, don't move yet
	if _state == "curious" and _wait_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_wait_timer -= _delta
		_update_animation(Vector2.ZERO)
		if _wait_timer <= 0.0:
			# Finished looking at flower, resume previous target with cooldown flagged to start on next move
			_current_flower_target = Vector2.ZERO
			_target_position = _saved_wander_target
			_rebuild_path_to_target()
			_should_restart_cooldown_on_move = true
			_state = "moving"
			_wait_timer = 0.0
			print("DEBUG: Finished looking at flower. Resuming target at %s with cooldown set to start on move" % [_saved_wander_target])
		return

	var dir := to_target.normalized()
	
	# Check if player is too close and handle collision avoidance
	var collision_dir = _handle_collision_avoidance(dir)
	if collision_dir != Vector2.ZERO:
		_target_position = _pick_far_target_in_direction(collision_dir)
		_rebuild_path_to_target()
		dir = (_get_current_path_target() - global_position).normalized()
	
	# Check if player is blocking the path
	_check_player_blocking(dir)
	
	# Ensure princess never steps outside the selected wander zone.
	var valid_dir := _find_valid_dir_inside_wander_zone(dir, _delta)
	if valid_dir == Vector2.ZERO:
		_handle_blocked_path("boundary")
		return
	dir = valid_dir
	
	# If we just finished looking at flower and are about to move, start the cooldown now
	if _should_restart_cooldown_on_move:
		_curious_cooldown_timer = randf_range(curious_cooldown_range.x, curious_cooldown_range.y)
		_should_restart_cooldown_on_move = false
		print("DEBUG: Starting cooldown (%.1fs) as queen begins moving" % [_curious_cooldown_timer])
	
	var desired_velocity := dir * move_speed
	var stair_type := _get_stair_type()
	if stair_type != "":
		if stair_type != "stair-m":
			desired_velocity = _apply_stair_bias_velocity(desired_velocity, stair_type)

	velocity = desired_velocity
	move_and_slide()
	if get_slide_collision_count() > 0:
		_handle_blocked_path("obstacle")
		return

	var move_dir := velocity.normalized()
	if move_dir == Vector2.ZERO:
		move_dir = dir
	_last_dir = move_dir
	_update_animation(move_dir)
	_update_stuck_state(_delta)

	if _stuck_timer >= stuck_time_seconds:
		print("DEBUG: Princess stuck at position %s after %.1f seconds of no progress. Attempting escape with random direction." % [global_position, stuck_time_seconds])
		_handle_blocked_path("stuck")


func _random_point_in_wander_area() -> Vector2:
	if wander_polygon.size() >= 3:
		return _random_point_in_wander_polygon()

	var x := randf_range(wander_area.position.x, wander_area.end.x)
	var y := randf_range(wander_area.position.y, wander_area.end.y)
	return Vector2(x, y)


func _random_point_in_wander_polygon() -> Vector2:
	for _i in 80:
		var x := randf_range(_wander_polygon_bounds.position.x, _wander_polygon_bounds.end.x)
		var y := randf_range(_wander_polygon_bounds.position.y, _wander_polygon_bounds.end.y)
		var p := Vector2(x, y)
		if Geometry2D.is_point_in_polygon(p, wander_polygon):
			return p

	# Fallback for very thin polygons.
	if wander_polygon.size() > 0:
		return wander_polygon[randi() % wander_polygon.size()]
	return global_position


func _compute_polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(global_position, Vector2.ONE)

	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y

	for p in points:
		if p.x < min_x:
			min_x = p.x
		if p.x > max_x:
			max_x = p.x
		if p.y < min_y:
			min_y = p.y
		if p.y > max_y:
			max_y = p.y

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _is_inside_wander_area(point: Vector2) -> bool:
	if wander_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, wander_polygon)
	if strict_polygon_only:
		return false
	return wander_area.has_point(point)


func _find_valid_dir_inside_wander_zone(preferred_dir: Vector2, delta: float) -> Vector2:
	if preferred_dir == Vector2.ZERO:
		return Vector2.ZERO

	var try_dirs: Array[Vector2] = [preferred_dir]
	for degrees in [25.0, 45.0, 70.0, 95.0, 120.0, 150.0]:
		var angle := deg_to_rad(degrees)
		try_dirs.append(preferred_dir.rotated(angle))
		try_dirs.append(preferred_dir.rotated(-angle))

	for candidate in try_dirs:
		var next_pos := global_position + candidate.normalized() * move_speed * delta
		if _is_inside_wander_area(next_pos):
			return candidate.normalized()

	return Vector2.ZERO


func _handle_blocked_path(reason: String = "obstacle") -> void:
	if _reroute_lock_timer > 0.0:
		return

	var turn_dir := _last_dir
	if reason == "obstacle":
		turn_dir = _pick_random_turn_direction()
	elif reason == "stuck":
		# When stuck, ALWAYS pick a random turn direction to escape
		turn_dir = _pick_random_turn_direction()
	elif turn_dir == Vector2.ZERO:
		turn_dir = Vector2.RIGHT

	if _state == "curious":
		_current_flower_target = Vector2.ZERO
		_curious_cooldown_timer = randf_range(curious_cooldown_range.x, curious_cooldown_range.y)
		if reason == "obstacle":
			_target_position = _pick_far_target_in_direction(turn_dir)
		else:
			_target_position = _pick_next_target_with_direction_change()
		_rebuild_path_to_target()
		_reroute_lock_timer = reroute_lock_seconds
		_wait_timer = 0.0
		_state = "moving"
		_stuck_timer = 0.0
		return

	velocity = Vector2.ZERO
	move_and_slide()

	if global_position.distance_to(_reroute_anchor) <= rapid_reroute_cluster_radius:
		_rapid_reroute_count += 1
		print("DEBUG: Rapid reroute #%d at position %s (still in cluster)" % [_rapid_reroute_count, global_position])
	else:
		_reroute_anchor = global_position
		_rapid_reroute_count = 1
		print("DEBUG: New reroute cluster at %s" % [global_position])

	if _rapid_reroute_count >= rapid_reroute_limit:
		if reason == "obstacle":
			_target_position = _pick_far_target_in_direction(turn_dir)
		else:
			_target_position = _pick_next_target_with_direction_change()
		_rebuild_path_to_target()
		_reroute_lock_timer = escape_commit_seconds
		_rapid_reroute_count = 0
		print("DEBUG: ESCAPING cluster after %d reroutes! New target at %s, commitment time %.1fs" % [rapid_reroute_limit, _target_position, escape_commit_seconds])
	else:
		if reason == "obstacle":
			_target_position = _pick_far_target_in_direction(turn_dir)
		else:
			_target_position = _pick_next_target_with_direction_change()
		_rebuild_path_to_target()
		_reroute_lock_timer = reroute_lock_seconds
		print("DEBUG: Local reroute to %s, lock time %.1fs" % [_target_position, reroute_lock_seconds])

	_wait_timer = 0.0
	_state = "moving"
	_stuck_timer = 0.0


func _pick_random_turn_direction() -> Vector2:
	var base_dir := _last_dir
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT

	# Try directions at 45-degree intervals to find a clear path
	var test_directions: Array[Vector2] = []
	var best_dir := base_dir
	var best_score := -10.0
	
	# Add directions at regular intervals
	for i in range(8):
		var angle := float(i) * PI / 4.0  # 45 degree steps
		test_directions.append(Vector2.RIGHT.rotated(angle))
	
	# Also try directions toward and away from target
	var to_target := _target_position - global_position
	if to_target.length() > 1.0:
		test_directions.append(to_target.normalized())  # Toward target
		test_directions.append(-to_target.normalized())  # Away from target
	
	# Score each direction
	for dir in test_directions:
		var score := 1.0
		
		# Check if direction is clear (use a short raycast ahead)
		var test_distance := 30.0
		var next_pos := global_position + dir * test_distance
		
		# If next position is inside wander area and not immediately blocked, it's good
		if _is_inside_wander_area(next_pos):
			score += 2.0  # Bonus for staying in bounds
		
		# Bonus if moving toward target
		if to_target.length() > 1.0:
			var alignment := dir.dot(to_target.normalized())
			score += alignment  # Range -1 to 1, bonus for moving toward target
		
		if score > best_score:
			best_score = score
			best_dir = dir
	
	print("DEBUG: Smart turn picked direction %s with score %.1f" % [best_dir, best_score])
	return best_dir.normalized()


func _pick_next_target_with_direction_change() -> Vector2:
	var chosen := _random_point_in_wander_area()
	var best_score := -INF

	for _i in target_pick_attempts:
		var candidate := _pick_raw_target()
		var to_candidate := candidate - global_position
		var candidate_dist := to_candidate.length()
		if candidate_dist < minimum_target_distance:
			continue
		
		# Skip targets blocked by obstacles/walls
		if not _has_line_of_sight(candidate):
			continue

		var cand_dir := to_candidate.normalized()
		var direction_change_score: float = 1.0 - clamp(cand_dir.dot(_last_dir), -1.0, 1.0)
		var far_score: float = min(candidate_dist / max(preferred_target_distance, 1.0), 2.0)
		var score: float = direction_change_score + far_score

		if candidate_dist >= preferred_target_distance:
			score += 0.7

		# Ensure targets are within visible range (view distance penalty for very far targets)
		if candidate_dist > max_view_distance:
			score *= 0.4  # Heavy penalty for targets outside view distance

		if score > best_score:
			best_score = score
			chosen = candidate

	return chosen


func _pick_far_target_in_direction(dir: Vector2) -> Vector2:
	var best := _pick_next_target_with_direction_change()
	var best_score := -INF

	for _i in target_pick_attempts:
		var candidate := _pick_raw_target()
		var to_candidate := candidate - global_position
		var candidate_dist := to_candidate.length()
		if candidate_dist < minimum_target_distance:
			continue
		
		# Skip targets blocked by obstacles/walls
		if not _has_line_of_sight(candidate):
			continue

		var cdir := to_candidate.normalized()
		var align: float = clamp(cdir.dot(dir.normalized()), -1.0, 1.0)
		var score: float = align + min(candidate_dist / max(preferred_target_distance, 1.0), 1.6)
		
		# Ensure targets are within visible range
		if candidate_dist > max_view_distance:
			score *= 0.4  # Heavy penalty for targets outside view distance
		
		if score > best_score:
			best_score = score
			best = candidate

	return best


func _pick_raw_target() -> Vector2:
	var choose_flower := flower_spots.size() > 0 and _curious_cooldown_timer <= 0.0 and randf() < flower_visit_chance
	if choose_flower:
		var reachable_flower := _pick_reachable_flower_target()
		if reachable_flower != Vector2.ZERO:
			return reachable_flower

	var choose_checkpoint := checkpoints.size() > 0 and randf() < checkpoint_visit_chance
	if choose_checkpoint:
		return checkpoints[randi() % checkpoints.size()]
	return _random_point_in_wander_area()


func _update_stuck_state(delta: float) -> void:
	var progressed := global_position.distance_to(_last_progress_position)
	if progressed < stuck_distance_threshold:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_progress_position = global_position


func _pick_look_point() -> Vector2:
	if checkpoints.size() == 0:
		return _random_point_in_wander_area()

	if checkpoints.size() == 1:
		return checkpoints[0]

	var best := checkpoints[0]
	var best_dist := -1.0
	for p in checkpoints:
		var d := global_position.distance_to(p)
		if d > best_dist:
			best_dist = d
			best = p
	return best

func _handle_collision_avoidance(dir: Vector2) -> Vector2:
	if not _player_ref:
		return Vector2.ZERO
	
	var to_player := _player_ref.global_position - global_position
	var dist_to_player := to_player.length()
	
	# If player is too close, calculate avoidance direction
	if dist_to_player < _collision_avoidance_distance:
		var player_dir := to_player.normalized()
		# If player is in front, go around them
		if player_dir.dot(dir) > 0.3:
			# Get perpendicular direction (rotate 90 degrees)
			var perpendicular = player_dir.rotated(PI / 2.0)
			if randf() < 0.5:
				perpendicular = player_dir.rotated(-PI / 2.0)
			return perpendicular.normalized()
	
	return Vector2.ZERO

func _is_close_to_any_checkpoint(point: Vector2) -> bool:
	for p in checkpoints:
		if point.distance_to(p) <= 32.0:
			return true
	return false


func _is_close_to_any_flower(point: Vector2) -> bool:
	for p in flower_spots:
		if point.distance_to(p) <= 28.0:
			return true
	return false


func _has_line_of_sight(target_pos: Vector2) -> bool:
	# Check if there's a clear line of sight to the target (not blocked by obstacles)
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true  # No space state, assume visible
	
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [self]
	query.collision_mask = collision_mask
	
	var result := space_state.intersect_ray(query)
	
	# If raycast hit nothing, we have clear line of sight
	if result.is_empty():
		return true
	
	# If raycast hit the target itself or very close to it, we can see it
	var hit_collider = result.get("collider")
	if hit_collider == null:
		return true
	
	var hit_pos = result.get("position", Vector2.ZERO)
	var distance_to_hit = hit_pos.distance_to(target_pos)
	
	# If the hit is very close to target (within 15 pixels), we can reach/see it
	return distance_to_hit <= 15.0


func _update_animation(move_dir: Vector2) -> void:
	var anim := ""

	if move_dir == Vector2.ZERO:
		anim = _get_idle_anim(_last_dir)
	else:
		anim = _get_walk_anim(move_dir)

	if anim != _current_anim and _sprite:
		_current_anim = anim
		_sprite.play(anim)


func _get_walk_anim(d: Vector2) -> String:
	if d.y < -0.5 and abs(d.x) < 0.5:
		return "walk-n"
	elif d.y > 0.5 and abs(d.x) < 0.5:
		return "walk-s"
	elif d.x > 0.5 and abs(d.y) < 0.5:
		return "walk-e"
	elif d.x < -0.5 and abs(d.y) < 0.5:
		return "walk-w"
	elif d.x > 0 and d.y < 0:
		return "walk-ne"
	elif d.x < 0 and d.y < 0:
		return "walk-nw"
	elif d.x > 0 and d.y > 0:
		return "walk-se"
	else:
		return "walk-sw"


func _get_idle_anim(d: Vector2) -> String:
	if d.y < -0.5 and abs(d.x) < 0.5:
		return "idle-n"
	elif d.y > 0.5 and abs(d.x) < 0.5:
		return "idle-s"
	elif d.x > 0.5 and abs(d.y) < 0.5:
		return "idle-e"
	elif d.x < -0.5 and abs(d.y) < 0.5:
		return "idle-w"
	elif d.x > 0 and d.y < 0:
		return "idle-ne"
	elif d.x < 0 and d.y < 0:
		return "idle-nw"
	elif d.x > 0 and d.y > 0:
		return "idle-se"
	else:
		return "idle-sw"


func _check_player_blocking(dir: Vector2) -> void:
	if not _player_ref:
		return
	
	var to_player := _player_ref.global_position - global_position
	var dist_to_player := to_player.length()
	
	# Check if player is close and in front of the princess
	if dist_to_player < _blocking_distance:
		var player_dir := to_player.normalized()
		# If player is roughly in the direction princess is walking, show dialogue
		if player_dir.dot(dir) > 0.6:  # 0.6 allows for ~53 degree cone
			_on_player_blocking_event()


func _on_player_blocking_event() -> void:
	if _block_event_timer > 0.0:
		return

	_block_event_timer = _block_event_cooldown

	# User asked for random rage increase when bodyguard blocks path.
	_rage_value = clamp(_rage_value + randf_range(rage_gain_min, rage_gain_max), 0.0, 100.0)
	_update_emotion_ui()
	_show_dialogue()


func _update_fear_from_proximity(delta: float) -> void:
	if _player_ref == null:
		_fear_value = min(100.0, _fear_value + fear_far_gain_per_second * delta)
		return

	var dist := global_position.distance_to(_player_ref.global_position)
	if dist <= fear_near_distance:
		_fear_value = max(0.0, _fear_value - fear_near_drop_per_second * delta)
		return

	if dist >= fear_far_distance:
		_fear_value = min(100.0, _fear_value + fear_far_gain_per_second * delta)
		return

	var t: float = (dist - fear_near_distance) / max(fear_far_distance - fear_near_distance, 1.0)
	var rate: float = lerp(-fear_near_drop_per_second, fear_far_gain_per_second, t)
	_fear_value = clamp(_fear_value + rate * delta, 0.0, 100.0)


func _get_stair_type() -> String:
	if _tilemap == null:
		return ""

	var cell: Vector2i = _tilemap.local_to_map(_tilemap.to_local(global_position))
	var data: TileData = _tilemap.get_cell_tile_data(0, cell)
	if data == null:
		return ""

	var t = data.get_custom_data("type")
	if typeof(t) == TYPE_STRING:
		return t
	return ""


func _apply_stair_bias_velocity(vel: Vector2, stair_type: String) -> Vector2:
	var bias := 0.0
	var right_up := false

	match stair_type:
		"stair-r":
			bias = queen_stair_bias
			right_up = true
		"stair-l":
			bias = queen_stair_bias
			right_up = false
		"stair-r2":
			bias = queen_stair_bias2
			right_up = true
		"stair-l2":
			bias = queen_stair_bias2
			right_up = false
		_:
			return vel

	if abs(vel.x) > abs(vel.y):
		if right_up:
			vel.y += -bias if vel.x > 0 else bias
		else:
			vel.y += -bias if vel.x < 0 else bias

	return vel


func _try_enter_curious_mode() -> void:
	_try_curious_counter += 1
	
	if _curious_cooldown_timer > 0.0:
		if _try_curious_counter % 60 == 0:
			print("DEBUG: Cooldown still active: %.1fs remaining" % [_curious_cooldown_timer])
		return
	if flower_spots.is_empty():
		if _try_curious_counter % 60 == 0:
			print("DEBUG: No flowers available - flower_spots is empty" )
		return

	var nearest := Vector2.ZERO
	var nearest_dist := INF
	for f in flower_spots:
		if not _is_inside_wander_area(f):
			continue
		var d := global_position.distance_to(f)
		if d < nearest_dist:
			nearest_dist = d
			nearest = f

	if nearest_dist > curious_trigger_distance:
		if _try_curious_counter % 300 == 0:
			print("DEBUG: Nearest flower %.1f away, trigger is %.1f" % [nearest_dist, curious_trigger_distance])
		return
	
	# Check if the flower is visible (not blocked by walls/objects)
	if not _has_line_of_sight(nearest):
		if _try_curious_counter % 300 == 0:
			print("DEBUG: Nearest flower is blocked by obstacle, cannot see it")
		return

	print(">>>TRYING CURIOUS: Distance %.1f, Position %s, Attempt #%d" % [nearest_dist, global_position, _try_curious_counter])
	
	# Try to find a good watch spot around the flower
	var watch_spot := _pick_flower_watch_spot(nearest)
	
	# If no good watch spot found, just go directly to the flower
	if watch_spot == Vector2.ZERO:
		watch_spot = nearest
		print("DEBUG: No watch spot, using flower at %s" % [watch_spot])

	# Always allow entry if flower is reasonably close, regardless of reachability
	# The physics system and stuck detection will handle unreachable flowers
	_saved_wander_target = _target_position  # Save current target before entering curious mode
	_current_flower_target = nearest
	_target_position = watch_spot
	_rebuild_path_to_target()
	_state = "curious"
	_just_finished_looking_at_flower = false
	_should_restart_cooldown_on_move = false
	print(">>>SUCCESS! CURIOUS MODE ACTIVE! Flower: %s, Watch: %s (Saved target: %s)" % [nearest, watch_spot, _saved_wander_target])


func _pick_reachable_flower_target() -> Vector2:
	var best := Vector2.ZERO
	var best_dist := INF

	for f in flower_spots:
		if not _is_inside_wander_area(f):
			continue
		if not _is_flower_reachable(f):
			continue

		var d := global_position.distance_to(f)
		if d < best_dist:
			best_dist = d
			best = f

	return best


func _pick_flower_watch_spot(flower_pos: Vector2) -> Vector2:
	# Try to find a watch spot around the flower in concentric circles outward
	var attempt := 0
	for _i in 30:  # Increased attempts
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(curious_watch_distance_range.x, curious_watch_distance_range.y)
		var candidate := flower_pos + Vector2.RIGHT.rotated(angle) * dist
		
		# Less strict: just check if inside wander area
		if _is_inside_wander_area(candidate):
			attempt += 1
			# Skip the reachability check to be more permissive
			print("DEBUG: Found watch spot attempt #%d at %s" % [attempt, candidate])
			return candidate
	
	print("DEBUG: Could not find any valid watch spot around flower in 30 attempts")
	return Vector2.ZERO


func _is_flower_reachable(flower_pos: Vector2) -> bool:
	return _is_point_reachable(flower_pos)


func _is_watch_spot_reachable(target_pos: Vector2) -> bool:
	if not _is_inside_wander_area(target_pos):
		return false

	var nav_map := get_world_2d().navigation_map
	if use_navigation_pathfinding and nav_map.is_valid() and NavigationServer2D.map_get_iteration_id(nav_map) > 0:
		var path := NavigationServer2D.map_get_path(nav_map, global_position, target_pos, true)
		if path.size() < 2:
			return false
		var end_point: Vector2 = path[path.size() - 1]
		return end_point.distance_to(target_pos) <= max(arrive_distance * 2.0, 24.0)

	# Without nav mesh, allow flower watch spot and let runtime collision/stuck logic resolve obstacles.
	return true


func _is_point_reachable(target_pos: Vector2) -> bool:
	if not _is_inside_wander_area(target_pos):
		return false

	var nav_map := get_world_2d().navigation_map
	if use_navigation_pathfinding and nav_map.is_valid() and NavigationServer2D.map_get_iteration_id(nav_map) > 0:
		var path := NavigationServer2D.map_get_path(nav_map, global_position, target_pos, true)
		if path.size() < 2:
			return false
		var end_point: Vector2 = path[path.size() - 1]
		return end_point.distance_to(target_pos) <= max(arrive_distance * 2.0, 24.0)

	# Fallback when no nav mesh: require direct line-of-sight to prevent endless blocked pursuit.
	var space_state := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	var hit := space_state.intersect_ray(params)
	return hit.is_empty()


func _rebuild_path_to_target() -> void:
	_path_points.clear()
	_path_index = 0

	if not use_navigation_pathfinding:
		_path_points.append(_target_position)
		return

	var nav_map := get_world_2d().navigation_map
	if nav_map.is_valid() and NavigationServer2D.map_get_iteration_id(nav_map) > 0:
		var path := NavigationServer2D.map_get_path(nav_map, global_position, _target_position, true)
		for p in path:
			if _is_inside_wander_area(p):
				_path_points.append(p)

	if _path_points.is_empty():
		_path_points.append(_target_position)

	if _path_points.size() > 1 and global_position.distance_to(_path_points[0]) <= arrive_distance:
		_path_index = 1


func _get_current_path_target() -> Vector2:
	if _path_points.is_empty():
		return _target_position
	return _path_points[clamp(_path_index, 0, _path_points.size() - 1)]


func _advance_path_target() -> bool:
	if _path_index < _path_points.size() - 1:
		_path_index += 1
		return true
	return false


func _show_dialogue() -> void:
	if not _dialogue_panel or not _dialogue_label:
		return
	
	_showing_dialogue = true
	_dialogue_timer = _dialogue_display_time
	
	# Use harsher tone when rage is high.
	var lines := _normal_dialogue_lines
	if _rage_value >= harsh_rage_threshold:
		lines = _harsh_dialogue_lines

	var dialogue = lines[randi() % lines.size()]
	_dialogue_label.text = dialogue
	_dialogue_panel.visible = true


func _clear_dialogue() -> void:
	_showing_dialogue = false
	if _dialogue_panel:
		_dialogue_panel.visible = false
	if _dialogue_label:
		_dialogue_label.text = ""


func _create_emotion_ui() -> void:
	if not is_inside_tree():
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	_hud_layer = scene_root.get_node_or_null("QueenHudLayer") as CanvasLayer
	if _hud_layer == null:
		_hud_layer = CanvasLayer.new()
		_hud_layer.name = "QueenHudLayer"
		_hud_layer.layer = 10
		scene_root.add_child(_hud_layer)

	_emotion_panel = PanelContainer.new()
	_emotion_panel.position = Vector2(12.0, 12.0)
	_emotion_panel.size = Vector2(312, 126)
	_emotion_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.08, 0.82)
	panel_style.border_color = Color(0.9, 0.9, 0.9, 0.95)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.corner_radius_bottom_right = 5
	_emotion_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var rage_title := Label.new()
	rage_title.text = "Rage"
	rage_title.add_theme_font_size_override("font_size", 11)
	rage_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45, 1.0))

	_rage_bar = ProgressBar.new()
	_rage_bar.min_value = 0
	_rage_bar.max_value = 100
	_rage_bar.value = _rage_value
	_rage_bar.show_percentage = false
	_rage_bar.custom_minimum_size = Vector2(292, 14)
	var rage_fill := StyleBoxFlat.new()
	rage_fill.bg_color = Color(0.9, 0.17, 0.17, 1.0)
	var rage_bg := StyleBoxFlat.new()
	rage_bg.bg_color = Color(0.18, 0.12, 0.12, 1.0)
	_rage_bar.add_theme_stylebox_override("fill", rage_fill)
	_rage_bar.add_theme_stylebox_override("background", rage_bg)

	var fear_title := Label.new()
	fear_title.text = "Fear"
	fear_title.add_theme_font_size_override("font_size", 11)
	fear_title.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0, 1.0))

	_fear_bar = ProgressBar.new()
	_fear_bar.min_value = 0
	_fear_bar.max_value = 100
	_fear_bar.value = _fear_value
	_fear_bar.show_percentage = false
	_fear_bar.custom_minimum_size = Vector2(292, 14)
	var fear_fill := StyleBoxFlat.new()
	fear_fill.bg_color = Color(0.2, 0.45, 1.0, 1.0)
	var fear_bg := StyleBoxFlat.new()
	fear_bg.bg_color = Color(0.12, 0.14, 0.2, 1.0)
	_fear_bar.add_theme_stylebox_override("fill", fear_fill)
	_fear_bar.add_theme_stylebox_override("background", fear_bg)

	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 9)
	_debug_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.custom_minimum_size = Vector2(292, 30)
	_debug_label.text = "Curious: false | Cooldown: 0.0s"

	root.add_child(rage_title)
	root.add_child(_rage_bar)
	root.add_child(fear_title)
	root.add_child(_fear_bar)
	root.add_child(_debug_label)
	_emotion_panel.add_child(root)
	_hud_layer.add_child(_emotion_panel)


func _update_emotion_ui() -> void:
	if _rage_bar:
		_rage_bar.value = _rage_value
	if _fear_bar:
		_fear_bar.value = _fear_value
	if _debug_label:
		var next_target: Vector2 = _get_current_path_target()
		var remaining: int = maxi(_path_points.size() - _path_index, 0)
		var cooldown: float = maxf(_curious_cooldown_timer, 0.0)
		_debug_label.text = "State: %s | Curious: %s | Cooldown: %.1fs | Flowers: %d\nNext: (%.0f, %.0f) | Path nodes: %d" % [
			_state,
			str(_state == "curious"),
			cooldown,
			flower_spots.size(),
			next_target.x,
			next_target.y,
			remaining
		]


func _draw() -> void:
	if not debug_show_path:
		return

	# Draw current target (yellow).
	var target_local := to_local(_target_position)
	draw_circle(target_local, 6.0, Color(1.0, 0.9, 0.2, 0.95))

	# Draw path from queen to current waypoint (cyan), then remaining path (green).
	if _path_points.is_empty():
		return

	var start := Vector2.ZERO
	if _path_index >= 0 and _path_index < _path_points.size():
		var current_wp := to_local(_path_points[_path_index])
		draw_line(start, current_wp, Color(0.2, 0.9, 1.0, 0.9), 2.0)

	var prev := Vector2.ZERO
	for i in range(_path_index, _path_points.size()):
		var wp := to_local(_path_points[i])
		if i > _path_index:
			draw_line(prev, wp, Color(0.35, 1.0, 0.4, 0.85), 2.0)
		draw_circle(wp, 3.0, Color(0.35, 1.0, 0.4, 0.95))
		prev = wp
