extends CharacterBody2D

# ==================== EXPORTS / CONFIG ====================

@export var move_speed := 42.0
@export var arrive_distance := 10.0
@export var debug_show_path := true

# Wander parameters
@export var minimum_target_distance := 90.0
@export var preferred_target_distance := 260.0
@export var max_view_distance := 450.0
@export var wander_wait_range := Vector2(0.8, 1.8)

# Flower/Curious mode parameters
@export var flower_trigger_distance := 520.0
@export var flower_cooldown_range := Vector2(11.0, 15.0)
@export var flower_pause_range := Vector2(1.5, 3.5)
@export var flower_watch_distance_range := Vector2(26.0, 44.0)

# Movement & collision
@export var stuck_threshold := 8.0
@export var stuck_time := 1.5
@export var collision_check_distance := 30.0

# Emotion system
@export var rage_max := 100.0
@export var fear_max := 100.0
@export var rage_decay := 1.2
@export var harsh_rage_threshold := 70.0
@export var fear_near_distance := 120.0
@export var fear_far_distance := 360.0
@export var player_fear_drop := 24.0
@export var player_fear_gain := 16.0

# ==================== STATE VARIABLES ====================

# State machine
var _state := "idle"  # idle, wandering, looking, moving_to_flower
var _previous_state := ""

# Position & movement
var _target_position := Vector2.ZERO
var _saved_wander_target := Vector2.ZERO
var _path_points: Array[Vector2] = []
var _path_index := 0
var _last_dir := Vector2.DOWN

# Timers & flags
var _wait_timer := 0.0
var _stuck_timer := 0.0
var _last_progress_pos := Vector2.ZERO
var _flower_cooldown := 0.0
var _reroute_lock := 0.0

# Flower tracking
var _current_flower := Vector2.ZERO
var _looking_at_flower := false

# Emotions
var _rage := 0.0
var _fear := 50.0

# Dialogue & UI
var _sprite: AnimatedSprite2D = null
var _player_ref: Node2D = null
var _tilemap: TileMap = null
var _dialogue_panel: PanelContainer = null
var _dialogue_label: Label = null
var _emotion_panel: PanelContainer = null
var _rage_bar: ProgressBar = null
var _fear_bar: ProgressBar = null
var _debug_label: Label = null

# World data
var wander_area := Rect2(Vector2(-300, -220), Vector2(600, 440))
var wander_polygon: PackedVector2Array = PackedVector2Array()
var checkpoints: Array[Vector2] = []
var flower_spots: Array[Vector2] = []

# ==================== LIFECYCLE ====================

func _ready() -> void:
	_sprite = $AnimatedSprite2D
	_player_ref = get_parent().get_node_or_null("player") as Node2D
	_tilemap = get_parent().get_node_or_null("TileMap") as TileMap
	
	# Disable camera/light from NPC
	if has_node("Camera2D"):
		$Camera2D.enabled = false
	if has_node("PointLight2D"):
		$PointLight2D.visible = false
	
	if _sprite == null:
		push_error("ERROR: AnimatedSprite2D not found!")
	
	_create_dialogue_ui()
	_state = "idle"
	_last_progress_pos = global_position

func configure_princess_behavior(
		area_rect: Rect2,
		checkpoint_positions: Array[Vector2],
		polygon_points: PackedVector2Array = PackedVector2Array(),
		flower_positions: Array[Vector2] = []) -> void:
	wander_area = area_rect
	wander_polygon = polygon_points
	checkpoints = checkpoint_positions
	flower_spots = flower_positions
	print("Queen AI: Configured with %d checkpoints, %d flowers" % [checkpoints.size(), flower_spots.size()])

func _physics_process(delta: float) -> void:
	# Update timers
	_flower_cooldown = maxf(_flower_cooldown - delta, 0.0)
	_reroute_lock = maxf(_reroute_lock - delta, 0.0)
	_wait_timer = maxf(_wait_timer - delta, 0.0)
	_stuck_timer = maxf(_stuck_timer - delta, 0.0) if _is_moving() else 0.0
	
	# Update emotions
	_rage = maxf(_rage - rage_decay * delta, 0.0)
	_update_fear(delta)
	
	# Main state machine
	_update_state_machine(delta)
	
	# Update UI
	_update_emotion_ui()
	if debug_show_path:
		queue_redraw()

func _update_state_machine(delta: float) -> void:
	_previous_state = _state
	
	match _state:
		"idle":
			_handle_idle_state(delta)
		"wandering":
			_handle_wandering_state(delta)
		"looking":
			_handle_looking_state(delta)
		"moving_to_flower":
			_handle_moving_to_flower_state(delta)

func _handle_idle_state(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_update_animation(Vector2.ZERO)
	
	if _wait_timer > 0.0:
		return
	
	# Check for nearby flowers
	if _can_be_curious():
		_enter_curious_mode()
		return
	
	# Start wandering
	_pick_new_wander_target()
	_state = "wandering"

func _handle_wandering_state(delta: float) -> void:
	if _target_position.distance_to(global_position) <= arrive_distance:
		# Arrived at target - patrol/look
		velocity = Vector2.ZERO
		move_and_slide()
		_state = "idle"
		_wait_timer = randf_range(wander_wait_range.x, wander_wait_range.y)
		_update_animation(Vector2.ZERO)
		return
	
	# Move toward target
	var to_target = _target_position - global_position
	var dir = to_target.normalized()
	
	# Move with collision detection
	velocity = dir * move_speed
	move_and_slide()
	
	# Check for obstacles
	if get_slide_collision_count() > 0:
		_handle_collision(delta)
		return
	
	# Update stuck detection
	var progressed = global_position.distance_to(_last_progress_pos)
	if progressed < stuck_threshold:
		_stuck_timer += delta
		if _stuck_timer >= stuck_time:
			print("Queen: Stuck! Rerouting...")
			_pick_new_wander_target()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
		_last_progress_pos = global_position
	
	_update_animation(dir)
	_last_dir = dir

func _handle_looking_state(delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_update_animation(Vector2.ZERO)
	
	# Check if wait timer has expired - finish looking
	if _wait_timer <= 0.0:
		_looking_at_flower = false
		print("Queen: Finished looking at flower")
	
	# If not looking anymore, resume wandering
	if not _looking_at_flower:
		# Set cooldown and return to wander target
		_flower_cooldown = randf_range(flower_cooldown_range.x, flower_cooldown_range.y)
		_target_position = _saved_wander_target
		_state = "wandering"
		print("Queen: Done looking. Cooldown: %.1fs, Resuming wander to %s" % [_flower_cooldown, _target_position])

func _handle_moving_to_flower_state(delta: float) -> void:
	if _current_flower.distance_to(global_position) <= arrive_distance:
		# Arrived at flower
		velocity = Vector2.ZERO
		move_and_slide()
		_looking_at_flower = true
		_state = "looking"
		_wait_timer = randf_range(flower_pause_range.x, flower_pause_range.y)
		_update_animation(Vector2.ZERO)
		print("Queen: Arrived at flower! Looking for %.1fs" % [_wait_timer])
		return
	
	# Move toward flower
	var to_flower = _current_flower - global_position
	var dir = to_flower.normalized()
	
	velocity = dir * move_speed
	move_and_slide()
	
	# Check for obstacles
	if get_slide_collision_count() > 0:
		print("Queen: Blocked while approaching flower")
		_pick_new_wander_target()
		_state = "wandering"
		return
	
	_update_animation(dir)
	_last_dir = dir

# ==================== CURIOUS MODE ====================

func _can_be_curious() -> bool:
	if _flower_cooldown > 0.0:
		return false
	if flower_spots.is_empty():
		return false
	
	# Find nearest flower
	var nearest := Vector2.ZERO
	var nearest_dist := INF
	
	for flower in flower_spots:
		var dist = global_position.distance_to(flower)
		if dist < flower_trigger_distance and dist < nearest_dist:
			nearest_dist = dist
			nearest = flower
	
	if nearest_dist == INF:
		return false
	
	# Check line of sight
	if not _has_line_of_sight(nearest):
		return false
	
	_current_flower = nearest
	return true

func _enter_curious_mode() -> void:
	_saved_wander_target = _target_position
	_target_position = _current_flower
	_looking_at_flower = false
	_state = "moving_to_flower"
	print("Queen: Curious! Heading to flower at %s (saved wander: %s)" % [_current_flower, _saved_wander_target])

# ==================== COLLISION & NAVIGATION ====================

func _handle_collision(delta: float) -> void:
	if _reroute_lock > 0.0:
		return
	
	print("Queen: Hit obstacle!")
	_pick_new_wander_target()
	_reroute_lock = 0.5
	_stuck_timer = 0.0

func _pick_new_wander_target() -> void:
	# Pick a random valid target point
	_target_position = _random_point_in_wander_area()
	_saved_wander_target = _target_position

func _random_point_in_wander_area() -> Vector2:
	if wander_polygon.size() >= 3:
		# Use polygon-based selection
		for _i in 50:
			var x = randf_range(wander_area.position.x, wander_area.end.x)
			var y = randf_range(wander_area.position.y, wander_area.end.y)
			var point = Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, wander_polygon):
				return point
		# Fallback to polygon center
		var sum = Vector2.ZERO
		for p in wander_polygon:
			sum += p
		return sum / float(wander_polygon.size())
	else:
		# Use rect-based selection
		return Vector2(
			randf_range(wander_area.position.x, wander_area.end.x),
			randf_range(wander_area.position.y, wander_area.end.y)
		)

func _is_inside_wander_area(point: Vector2) -> bool:
	if wander_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, wander_polygon)
	return wander_area.has_point(point)

func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	if space_state == null:
		return true
	
	var query = PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [self]
	query.collision_mask = collision_mask
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return true
	
	var hit_pos = result.get("position", Vector2.ZERO)
	return hit_pos.distance_to(target_pos) <= 15.0

# ==================== ANIMATION ====================

func _update_animation(move_dir: Vector2) -> void:
	if not _sprite:
		return
	
	var anim = ""
	if move_dir == Vector2.ZERO:
		# Idle animation based on last direction
		if _last_dir.y > 0.5:
			anim = "idle_down"
		elif _last_dir.y < -0.5:
			anim = "idle_up"
		elif _last_dir.x > 0.5:
			anim = "idle_right"
		else:
			anim = "idle_left"
	else:
		# Walking animation
		if move_dir.y > 0.5:
			anim = "walk_down"
		elif move_dir.y < -0.5:
			anim = "walk_up"
		elif move_dir.x > 0.5:
			anim = "walk_right"
		else:
			anim = "walk_left"
	
	# Only change animation if different
	if _sprite.animation != anim:
		_sprite.animation = anim
		_sprite.play()

# ==================== UI ====================

func _create_dialogue_ui() -> void:
	# Create dialogue panel
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.position = Vector2(-72.0, -104.0)
	_dialogue_panel.size = Vector2(144, 34)
	
	# Create HUD layer
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	add_child(_hud_layer)
	
	# Create emotion panel
	_emotion_panel = PanelContainer.new()
	_emotion_panel.position = Vector2(-150, -160)
	_emotion_panel.size = Vector2(300, 150)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	panel_style.border_color = Color(0.7, 0.7, 0.8, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	
	var theme = Theme.new()
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	_emotion_panel.theme = theme
	
	# Root vbox for emotion panel
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	
	# Rage bar
	var rage_title = Label.new()
	rage_title.text = "Rage:"
	rage_title.add_theme_font_size_override("font_size", 10)
	
	_rage_bar = ProgressBar.new()
	_rage_bar.min_value = 0.0
	_rage_bar.max_value = 100.0
	_rage_bar.custom_minimum_size = Vector2(280, 12)
	
	# Fear bar
	var fear_title = Label.new()
	fear_title.text = "Fear:"
	fear_title.add_theme_font_size_override("font_size", 10)
	
	_fear_bar = ProgressBar.new()
	_fear_bar.min_value = 0.0
	_fear_bar.max_value = 100.0
	_fear_bar.custom_minimum_size = Vector2(280, 12)
	
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 9)
	_debug_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.custom_minimum_size = Vector2(292, 30)
	_debug_label.text = "State: idle"
	
	root.add_child(rage_title)
	root.add_child(_rage_bar)
	root.add_child(fear_title)
	root.add_child(_fear_bar)
	root.add_child(_debug_label)
	_emotion_panel.add_child(root)
	_hud_layer.add_child(_emotion_panel)

func _update_emotion_ui() -> void:
	if _rage_bar:
		_rage_bar.value = _rage
	if _fear_bar:
		_fear_bar.value = _fear
	if _debug_label:
		_debug_label.text = "State: %s | Looking: %s | Cooldown: %.1fs | Flowers: %d" % [
			_state,
			str(_looking_at_flower),
			_flower_cooldown,
			flower_spots.size()
		]

func _update_fear(delta: float) -> void:
	if _player_ref == null:
		_fear = minf(_fear + player_fear_gain * delta, fear_max)
		return
	
	var dist = global_position.distance_to(_player_ref.global_position)
	if dist <= fear_near_distance:
		_fear = maxf(_fear - player_fear_drop * delta, 0.0)
	elif dist >= fear_far_distance:
		_fear = minf(_fear + player_fear_gain * delta, fear_max)

# ==================== UTILITY ====================

func _is_moving() -> bool:
	return _state in ["wandering", "moving_to_flower"]

func _draw() -> void:
	if not debug_show_path:
		return
	
	# Draw target position
	var target_local = to_local(_target_position)
	draw_circle(target_local, 6.0, Color(1.0, 0.9, 0.2, 0.95))
	
	# Draw current flower if looking
	if _looking_at_flower or _state == "moving_to_flower":
		var flower_local = to_local(_current_flower)
		draw_circle(flower_local, 8.0, Color(1.0, 0.5, 0.8, 0.9))
