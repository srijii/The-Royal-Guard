extends CharacterBody2D

signal died

const MIKO_SCENE: PackedScene = preload("res://scene/warden.tscn")
const OPTIONS_PATH := "user://options.cfg"

@export var speed := 100.0
@export var stair_speed := 60.0
@export var run_speed_multiplier := 1.65
@export var run_animation_fps_multiplier := 1.35
@export var start_with_lamp_on := false
@export var camera_zoom := Vector2(1.5, 1.5)
@export var zoom_out_on_hold := Vector2(0.6, 0.6)
@export var zoom_lerp_speed := 8.0

@export var stair_bias := 40.0    # for stair-r / stair-l
@export var stair_bias2 := 45.0   # for stair-r2 / stair-l2
@export var throw_friction := 1800.0
@export var throw_flip_interval := 0.05
@export var attack_damage := 40
@export var attack_range := 60.0
@export var attack_arc_degrees := 80.0
@export var attack_cooldown := 0.6
@export var attack_knockback_force := 360.0
@export var attack_animation_fps_multiplier := 1.7
@export var attack_lock_movement := false
@export var combat_knockback_decay := 1500.0
@export var regeneration_total_hearts := 5
@export var regeneration_heart_heal_amount := 12
@export var regeneration_first_tick_delay := 0.5
@export var regeneration_delay_step := 1.0
@export var strength_potion_duration := 20.0
@export var strength_potion_gain_percent := 20.0
@export var full_strength_damage_reduction := 0.30
@export var full_strength_min_attack_damage := 150
@export var attack_energy_cost_min := 8.0
@export var attack_energy_cost_max := 20.0
@export var max_energy := 100.0
@export var energy_gain_per_drink := 50.0
@export var energy_drain_per_second := 25.0
@export var energy_regen_standing := 6.0
@export var energy_regen_walking := 2.0
@export var max_strength := 100.0


var tilemap: TileMap = null
var animated_sprite: AnimatedSprite2D = null
var collision_shape: CollisionShape2D = null
var point_light: PointLight2D = null
var is_alive := true
var controls_enabled := true
var lamp_control_unlocked := false

# Health system for UI
@export var max_health := 100
var current_health := max_health

func take_damage(amount: int) -> void:
	var damage_amount := amount
	if _strength_value >= max_strength:
		damage_amount = int(round(float(amount) * (1.0 - full_strength_damage_reduction)))
		damage_amount = max(1, damage_amount)
	current_health = max(0, current_health - damage_amount)
	Helpers.spawn_blood_effect(global_position)
	Helpers.spawn_blood_stain(global_position)
	if current_health == 0:
		die()

func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)

func get_health_percent() -> float:
	return float(current_health) / float(max_health)


func _ensure_potion_input_actions() -> void:
	_ensure_action_key("attack", KEY_CTRL)
	_ensure_action_key("sprint", KEY_SHIFT)
	_ensure_action_key("hold_map_zoom", KEY_M)
	_ensure_action_key("use_health_potion", KEY_SPACE)
	_ensure_action_key("use_strength_potion", KEY_J)
	_ensure_action_key("use_energy_drink", KEY_K)


func _ensure_action_key(action_name: String, default_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	if InputMap.action_get_events(action_name).is_empty():
		var ev := InputEventKey.new()
		ev.keycode = default_keycode
		InputMap.action_add_event(action_name, ev)


func _set_action_key(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	InputMap.action_erase_events(action_name)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action_name, ev)


func _ensure_regeneration_timer() -> void:
	if _regeneration_timer != null:
		return
	_regeneration_timer = Timer.new()
	_regeneration_timer.one_shot = true
	_regeneration_timer.autostart = false
	add_child(_regeneration_timer)
	_regeneration_timer.timeout.connect(_on_regeneration_tick)

func die() -> void:
	if is_alive:
		is_alive = false
		emit_signal("died")

var last_dir := Vector2.UP
var current_anim := ""
var _throw_active := false
var _throw_velocity := Vector2.ZERO
var _throw_time_left := 0.0
var _throw_flip_timer := 0.0
var _throw_flip_right := false
var _is_running := false
var _skeleton_slow_factor := 1.0
var _skeleton_slow_time_left := 0.0
var _is_attacking := false
var _attack_time_left := 0.0
var _last_attack_energy_cost := 0.0
var _last_attack_used_strength := false

var _attack_duration := 0.0
var _attack_cooldown_left := 0.0
var _attack_hit_done := false
var _attack_facing_dir := Vector2.DOWN
var _camera_normal_zoom := Vector2.ONE
var _combat_knockback_velocity := Vector2.ZERO
var _potion_counts := {
	"health": 0,
	"strength": 0,
	"energy": 0,
}
var _wizard_key_count := 0
var _strength_buff_time_left := 0.0
var _energy_value := 0.0
var _strength_value := 0.0
var _regeneration_hearts_left := 0
var _regeneration_next_delay := 1.0
var _regeneration_timer: Timer = null
var _skeleton_regen_hearts_left := 0
var _skeleton_regen_timer: Timer = null
var _is_bleeding := false
var _bleeding_time_left := 0.0
var _bleeding_stain_timer := 0.0
var _map_unlocked := false
var _mobile_controls_enabled := false
var _mobile_layer: CanvasLayer = null
var _mobile_joystick_base: Panel = null
var _mobile_joystick_knob: Panel = null
var _mobile_joystick_touch_id := -1
var _mobile_joystick_center := Vector2.ZERO
var _mobile_joystick_radius := 62.0
var _mobile_move_vector := Vector2.ZERO
var _mobile_attack_pressed := false
var _mobile_sprint_pressed := false
var _mobile_map_pressed := false

var _mobile_btn_font: SystemFont = null
var _mobile_btn_infos: Array[Dictionary] = []
var _mobile_button_panels: Array[Panel] = []
var _last_btn_opacity := -1.0


func is_attacking() -> bool:
	return _is_attacking

func set_map_unlocked() -> void:
	_map_unlocked = true


func _ready():
	print("Player _ready() called")
	add_to_group("player")
	_ensure_potion_input_actions()
	_ensure_regeneration_timer()
	_setup_mobile_controls_if_enabled()
	_energy_value = max_energy * 0.5
	
	# Safely get references to child nodes
	animated_sprite = get_node_or_null("AnimatedSprite2D")
	if animated_sprite == null:
		push_error("AnimatedSprite2D not found in player!")
	else:
		print("AnimatedSprite2D found")
	
	collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape == null:
		push_error("CollisionShape2D not found in player!")
	else:
		print("CollisionShape2D found")

	point_light = get_node_or_null("PointLight2D") as PointLight2D
	if point_light:
		point_light.visible = start_with_lamp_on and lamp_control_unlocked

	var cam := _get_attached_camera()
	if cam:
		cam.zoom = camera_zoom
		_camera_normal_zoom = camera_zoom
	
	tilemap = get_parent().get_node_or_null("TileMap") as TileMap
	if tilemap == null:
		push_warning("TileMap not found in parent!")
	else:
		print("TileMap found successfully")
		_configure_camera_limits()
	
	
	print("Player initialization complete")


func _get_attached_camera() -> Camera2D:
	for child in get_children():
		if child is Camera2D:
			return child as Camera2D
	return null


func _configure_camera_limits() -> void:
	var cam := _get_attached_camera()
	if cam == null or tilemap == null:
		return

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

	var top_left_world: Vector2 = tilemap.to_global(top_left_local)
	var bottom_right_world: Vector2 = tilemap.to_global(bottom_right_local)

	cam.limit_enabled = true
	cam.limit_left = int(round(top_left_world.x))
	cam.limit_top = int(round(top_left_world.y))
	cam.limit_right = int(round(bottom_right_world.x))
	cam.limit_bottom = int(round(bottom_right_world.y))


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if _mobile_controls_enabled:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				if _mobile_joystick_touch_id == -1 and touch.position.distance_to(_mobile_joystick_center) <= _mobile_joystick_radius * 1.6:
					_mobile_joystick_touch_id = touch.index
					_update_mobile_joystick(touch.position)
					get_viewport().set_input_as_handled()
			elif touch.index == _mobile_joystick_touch_id:
				_mobile_joystick_touch_id = -1
				_reset_mobile_joystick()
				get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			if drag.index == _mobile_joystick_touch_id:
				_update_mobile_joystick(drag.position)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed:
				if _mobile_joystick_touch_id == -1 and mb.position.distance_to(_mobile_joystick_center) <= _mobile_joystick_radius * 1.6:
					_mobile_joystick_touch_id = 0
					_update_mobile_joystick(mb.position)
					get_viewport().set_input_as_handled()
			elif _mobile_joystick_touch_id == 0:
				_mobile_joystick_touch_id = -1
				_reset_mobile_joystick()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _mobile_joystick_touch_id == 0 and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_update_mobile_joystick(mm.position)
				get_viewport().set_input_as_handled()

		if _process_mobile_buttons_event(event):
			return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			if lamp_control_unlocked and point_light:
				point_light.visible = not point_light.visible

	if event.is_action_pressed("use_health_potion"):
		_use_health_potion()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_strength_potion"):
		_use_strength_potion()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_energy_drink"):
		_use_energy_drink()
		get_viewport().set_input_as_handled()


func _debug_spawn_or_move_miko_near_player() -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root

	var miko_node: Node2D = _find_node2d_by_name(root, "miko")
	if miko_node == null:
		if MIKO_SCENE == null:
			push_warning("Miko scene is not available.")
			return
		miko_node = MIKO_SCENE.instantiate() as Node2D
		if miko_node == null:
			push_warning("Failed to instantiate miko scene.")
			return
		miko_node.name = "miko"
		root.add_child(miko_node)

	var angle: float = randf_range(0.0, TAU)
	var dist: float = randf_range(56.0, 96.0)
	var spawn_pos: Vector2 = global_position + Vector2.RIGHT.rotated(angle) * dist
	miko_node.global_position = spawn_pos


func _find_node2d_by_name(node: Node, target_name: String) -> Node2D:
	if node.name == target_name and node is Node2D:
		return node as Node2D

	for child in node.get_children():
		var found: Node2D = _find_node2d_by_name(child, target_name)
		if found != null:
			return found

	return null


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled


func set_lamp_control_unlocked(enabled: bool) -> void:
	lamp_control_unlocked = enabled
	if point_light and not lamp_control_unlocked:
		point_light.visible = false


func is_lamp_control_unlocked() -> bool:
	return lamp_control_unlocked


func set_facing_south() -> void:
	last_dir = Vector2.DOWN
	update_animation(Vector2.ZERO)


func player() -> Node:
	return self


func force_kill_by_skeleton() -> void:
	if not is_alive:
		return

	is_alive = false
	controls_enabled = false
	_throw_active = false
	_throw_velocity = Vector2.ZERO
	velocity = Vector2.ZERO

	if collision_shape:
		collision_shape.disabled = true

	if animated_sprite:
		current_anim = get_idle_anim(last_dir)
		animated_sprite.play(current_anim)

	emit_signal("died")


func apply_uncontrolled_throw(from_position: Vector2, force := 520.0, duration := 0.45) -> void:
	var away := global_position - from_position
	if away.length_squared() < 0.0001:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	away = away.normalized()

	_throw_active = true
	_throw_velocity = away * force
	_throw_time_left = maxf(0.12, duration)
	_throw_flip_timer = 0.0
	_throw_flip_right = false


func apply_skeleton_slow(slow_multiplier := 3.0, duration := 1.8) -> void:
	# 3x slowness means movement speed becomes 1/3 for a short duration.
	var multiplier := maxf(1.0, slow_multiplier)
	var factor := 1.0 / multiplier
	_skeleton_slow_factor = minf(_skeleton_slow_factor, factor)
	_skeleton_slow_time_left = maxf(_skeleton_slow_time_left, duration)


func apply_skeleton_regen(hearts := 4, delay := 2.0) -> void:
	_ensure_skeleton_regen_timer()
	_skeleton_regen_hearts_left = max(_skeleton_regen_hearts_left, hearts)
	if not _skeleton_regen_timer.is_stopped():
		return
	_skeleton_regen_timer.start(delay)


func _ensure_skeleton_regen_timer() -> void:
	if _skeleton_regen_timer != null:
		return
	_skeleton_regen_timer = Timer.new()
	_skeleton_regen_timer.one_shot = false
	_skeleton_regen_timer.autostart = false
	add_child(_skeleton_regen_timer)
	_skeleton_regen_timer.timeout.connect(_on_skeleton_regen_tick)


func _on_skeleton_regen_tick() -> void:
	if _skeleton_regen_hearts_left <= 0:
		_skeleton_regen_timer.stop()
		return
	heal(6)
	_skeleton_regen_hearts_left -= 1
	var scene := get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Princess supports you with the ring's regeneration!", 2.0)


func start_bleeding(duration := 6.0) -> void:
	_is_bleeding = true
	_bleeding_time_left = duration
	_bleeding_stain_timer = 0.1


func _physics_process(delta):
	_update_camera_hold_zoom(delta)
	_update_combat_knockback(delta)

	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)

	if _strength_buff_time_left > 0.0:
		_strength_buff_time_left = maxf(0.0, _strength_buff_time_left - delta)
		if _strength_buff_time_left <= 0.0:
			_strength_value = 0.0

	if _skeleton_slow_time_left > 0.0:
		_skeleton_slow_time_left = maxf(0.0, _skeleton_slow_time_left - delta)
		if _skeleton_slow_time_left <= 0.0:
			_skeleton_slow_factor = 1.0

	if _is_bleeding:
		_bleeding_time_left = maxf(0.0, _bleeding_time_left - delta)
		_bleeding_stain_timer = maxf(0.0, _bleeding_stain_timer - delta)
		if _bleeding_stain_timer <= 0.0 and velocity.length() > 20.0:
			_bleeding_stain_timer = 0.2
			Helpers.spawn_blood_stain(global_position)
			Helpers.spawn_blood_effect(global_position)
		if _bleeding_time_left <= 0.0:
			_is_bleeding = false

	if _is_attacking:
		_process_attack(delta)

	if _throw_active:
		_is_running = false
		if animated_sprite:
			animated_sprite.speed_scale = 1.0
		_process_uncontrolled_throw(delta)
		return

	if not controls_enabled:
		_is_running = false
		if animated_sprite:
			animated_sprite.speed_scale = 1.0
		velocity = _combat_knockback_velocity
		move_and_slide()
		update_animation(Vector2.ZERO)
		return

	if (Input.is_action_pressed("attack") or _mobile_attack_pressed) and _attack_cooldown_left <= 0.0 and not _is_attacking:
		_start_attack()

	var input_dir := _get_move_input_vector()

	var stair_type := get_stair_type()
	var sprinting := _consume_energy_for_sprint(delta, input_dir)
	_is_running = sprinting

	if not sprinting and _energy_value < max_energy:
		var regen_rate := energy_regen_standing if input_dir == Vector2.ZERO else energy_regen_walking
		_energy_value = minf(max_energy, _energy_value + regen_rate * delta)

	if animated_sprite:
		animated_sprite.speed_scale = run_animation_fps_multiplier if _is_running else 1.0

	var base_speed := speed * (run_speed_multiplier if _is_running else 1.0)
	base_speed *= _skeleton_slow_factor
	var vel := input_dir.normalized() * base_speed

	if stair_type != "":
		var stair_move_speed := stair_speed * (run_speed_multiplier if _is_running else 1.0)
		stair_move_speed *= _skeleton_slow_factor
		vel = input_dir * stair_move_speed

		if stair_type != "stair-m":
			vel = apply_stair_bias_velocity(vel, stair_type)

	velocity = vel + _combat_knockback_velocity
	move_and_slide()

	if tilemap:
		global_position = _clamp_to_tilemap_bounds(global_position)

	if input_dir != Vector2.ZERO:
		last_dir = input_dir.normalized()

	var anim_dir := input_dir.normalized() if input_dir != Vector2.ZERO else Vector2.ZERO
	update_animation(anim_dir)
	_separate_from_other_players()


func _update_camera_hold_zoom(delta: float) -> void:
	var cam := _get_attached_camera()
	if cam == null:
		return

	var hold_zoom := _map_unlocked and (Input.is_action_pressed("hold_map_zoom") or _mobile_map_pressed)
	var target_zoom := zoom_out_on_hold if hold_zoom else _camera_normal_zoom
	cam.zoom = cam.zoom.lerp(target_zoom, clampf(zoom_lerp_speed * delta, 0.0, 1.0))


func _clamp_to_tilemap_bounds(pos: Vector2) -> Vector2:
	if tilemap == null:
		return pos

	var used_rect: Rect2i = tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return pos

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

	var top_left_world: Vector2 = tilemap.to_global(top_left_local)
	var bottom_right_world: Vector2 = tilemap.to_global(bottom_right_local)
	return Vector2(
		clampf(pos.x, top_left_world.x, bottom_right_world.x),
		clampf(pos.y, top_left_world.y, bottom_right_world.y)
	)


func _process_uncontrolled_throw(delta: float) -> void:
	_throw_time_left -= delta
	_throw_velocity = _throw_velocity.move_toward(Vector2.ZERO, throw_friction * delta)
	velocity = _throw_velocity
	move_and_slide()

	_throw_flip_timer -= delta
	if _throw_flip_timer <= 0.0:
		_throw_flip_timer = throw_flip_interval
		_throw_flip_right = not _throw_flip_right
		if animated_sprite:
			current_anim = "walk-e" if _throw_flip_right else "walk-w"
			animated_sprite.play(current_anim)

	if _throw_time_left <= 0.0 or _throw_velocity.length() <= 15.0:
		_throw_active = false


func _start_attack() -> void:
	if not controls_enabled or not is_alive or animated_sprite == null:
		return

	var cost := randf_range(attack_energy_cost_min, attack_energy_cost_max)
	if _strength_value > 0.0:
		cost = minf(cost, _strength_value)
		_strength_value -= cost
		_last_attack_used_strength = true
	elif _energy_value > 0.0:
		cost = minf(cost, _energy_value)
		_energy_value -= cost
		_last_attack_used_strength = false
	else:
		cost = 0.0
		_last_attack_used_strength = false
	_last_attack_energy_cost = cost

	_is_attacking = true
	_attack_hit_done = false
	_attack_cooldown_left = attack_cooldown
	velocity = Vector2.ZERO
	_attack_facing_dir = _get_attack_facing_direction()

	var attack_anim: String = get_attack_anim(_attack_facing_dir)
	current_anim = attack_anim
	animated_sprite.speed_scale = attack_animation_fps_multiplier
	animated_sprite.play(attack_anim)

	var anim_speed: float = maxf(0.01, animated_sprite.sprite_frames.get_animation_speed(attack_anim))
	var frame_count: int = max(1, animated_sprite.sprite_frames.get_frame_count(attack_anim))
	var effective_anim_speed := anim_speed * maxf(0.1, attack_animation_fps_multiplier)
	_attack_duration = float(frame_count) / effective_anim_speed
	_attack_time_left = _attack_duration


func _process_attack(delta: float) -> void:
	if not is_alive:
		_is_attacking = false
		return

	if animated_sprite:
		var atk_anim: String = get_attack_anim(_attack_facing_dir)
		if current_anim != atk_anim:
			current_anim = atk_anim
			animated_sprite.play(atk_anim)
		animated_sprite.speed_scale = attack_animation_fps_multiplier

	if attack_lock_movement:
		velocity = _combat_knockback_velocity
		move_and_slide()

	var hit_trigger_time_left := _attack_duration * 0.5
	if not _attack_hit_done and _attack_time_left <= hit_trigger_time_left:
		_attack_hit_done = true
		_do_attack_hit()

	_attack_time_left = maxf(0.0, _attack_time_left - delta)
	if _attack_time_left <= 0.0:
		_is_attacking = false
		update_animation(Vector2.ZERO)


func _do_attack_hit() -> void:
	var facing: Vector2 = _attack_facing_dir
	if facing.length_squared() < 0.0001:
		facing = Vector2.DOWN
	facing = facing.normalized()

	var fx_target := global_position + facing * attack_range
	_spawn_player_attack_fx(fx_target, facing)

	var energy_mult := 1.0 + (_last_attack_energy_cost / 10.0)
	var total_damage := int(round(float(attack_damage) * energy_mult))
	if _last_attack_used_strength:
		total_damage += int(_last_attack_energy_cost * 2.5)
		total_damage = max(total_damage, full_strength_min_attack_damage)

	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var arc_cos: float = cos(deg_to_rad(attack_arc_degrees * 0.5))
	for enemy: Node in enemies:
		if enemy == null or enemy == self or not (enemy is Node2D):
			continue

		var enemy_pos: Vector2 = (enemy as Node2D).global_position
		var to_enemy: Vector2 = enemy_pos - global_position
		var dist: float = to_enemy.length()
		if dist > attack_range or dist <= 0.0001:
			continue

		var dir_to_enemy: Vector2 = to_enemy / dist
		if facing.dot(dir_to_enemy) < arc_cos:
			continue

		if enemy.has_method("take_damage"):
			enemy.call("take_damage", total_damage)
		if enemy.has_method("apply_combat_knockback"):
			enemy.call("apply_combat_knockback", global_position, attack_knockback_force)

		Helpers.spawn_blood_effect(enemy_pos)


func _spawn_player_attack_fx(target_position: Vector2, facing_dir: Vector2) -> void:
	var fx_root := get_tree().current_scene
	if fx_root == null:
		fx_root = get_tree().root

	var slash := Node2D.new()
	slash.global_position = global_position
	slash.rotation = atan2(facing_dir.y, facing_dir.x)
	fx_root.add_child(slash)

	var arc := Polygon2D.new()
	var arc_points := PackedVector2Array()
	var arc_radius := 28.0
	var arc_angle := deg_to_rad(55.0)
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := -arc_angle + t * 2.0 * arc_angle
		arc_points.append(Vector2(cos(a) * arc_radius, sin(a) * arc_radius))
	for i in range(steps, -1, -1):
		var t := float(i) / float(steps)
		var a := -arc_angle + t * 2.0 * arc_angle
		arc_points.append(Vector2(cos(a) * arc_radius * 0.65, sin(a) * arc_radius * 0.65))
	arc.polygon = arc_points
	arc.color = Color(1.0, 0.72, 0.18, 0.9)
	arc.offset = Vector2(6.0, 0.0)
	slash.add_child(arc)

	for i in range(5):
		var spark := Line2D.new()
		spark.width = 1.8
		spark.default_color = Color(1.0, 0.6, 0.1, 0.95)
		var spread := (float(i) - 2.0) * 4.0
		spark.points = PackedVector2Array([
			Vector2(spread, spread * 0.3),
			Vector2(spread + 20.0 + randf_range(-4.0, 4.0), spread * -0.3 + randf_range(-2.0, 2.0))
		])
		slash.add_child(spark)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "global_position", target_position, 0.15)
	tween.tween_property(slash, "modulate:a", 0.0, 0.15)
	tween.tween_property(arc, "scale", Vector2(1.4, 1.4), 0.15)
	tween.finished.connect(func() -> void:
		if is_instance_valid(slash):
			slash.queue_free()
	)


func _update_combat_knockback(delta: float) -> void:
	if _combat_knockback_velocity.length() > 0.01:
		_combat_knockback_velocity = _combat_knockback_velocity.move_toward(Vector2.ZERO, combat_knockback_decay * delta)


func apply_combat_knockback(from_position: Vector2, force := 260.0) -> void:
	var away := global_position - from_position
	if away.length_squared() < 0.0001:
		away = last_dir if last_dir.length_squared() > 0.0001 else Vector2.DOWN
	away = away.normalized()
	_combat_knockback_velocity += away * force


func add_potion_item(potion_type: String) -> void:
	if not _potion_counts.has(potion_type):
		return
	_potion_counts[potion_type] = int(_potion_counts[potion_type]) + 1


func get_potion_count(potion_type: String) -> int:
	if not _potion_counts.has(potion_type):
		return 0
	return int(_potion_counts[potion_type])


func add_wizard_key() -> void:
	_wizard_key_count += 1


func get_wizard_key_count() -> int:
	return _wizard_key_count


func get_energy_percent() -> float:
	return clampf((_energy_value / maxf(1.0, max_energy)) * 100.0, 0.0, 100.0)


func get_strength_percent() -> float:
	return clampf((_strength_value / maxf(1.0, max_strength)) * 100.0, 0.0, 100.0)


func _use_health_potion() -> void:
	if int(_potion_counts["health"]) <= 0:
		return
	if current_health >= max_health:
		return
	_potion_counts["health"] = int(_potion_counts["health"]) - 1
	_start_regeneration_effect()


func _start_regeneration_effect() -> void:
	_ensure_regeneration_timer()
	_regeneration_hearts_left = max(1, regeneration_total_hearts)
	_regeneration_next_delay = maxf(0.1, regeneration_first_tick_delay)
	if _regeneration_timer:
		_regeneration_timer.stop()
		_regeneration_timer.start(_regeneration_next_delay)


func _on_regeneration_tick() -> void:
	if _regeneration_hearts_left <= 0:
		return

	heal(regeneration_heart_heal_amount)
	_regeneration_hearts_left -= 1

	if current_health >= max_health:
		_regeneration_hearts_left = 0

	if _regeneration_hearts_left <= 0:
		return

	_regeneration_next_delay += maxf(0.0, regeneration_delay_step)
	if _regeneration_timer:
		_regeneration_timer.start(_regeneration_next_delay)


func _use_strength_potion() -> void:
	if int(_potion_counts["strength"]) <= 0:
		return
	if _strength_value >= max_strength:
		return
	_potion_counts["strength"] = int(_potion_counts["strength"]) - 1
	var gain_amount := (max_strength * strength_potion_gain_percent) / 100.0
	_strength_value = clampf(_strength_value + gain_amount, 0.0, max_strength)
	_strength_buff_time_left = strength_potion_duration


func _use_energy_drink() -> void:
	if int(_potion_counts["energy"]) <= 0:
		return
	if _energy_value >= max_energy:
		return
	_potion_counts["energy"] = int(_potion_counts["energy"]) - 1
	_energy_value = clampf(_energy_value + energy_gain_per_drink, 0.0, max_energy)


func _consume_energy_for_sprint(delta: float, input_dir: Vector2) -> bool:
	if input_dir == Vector2.ZERO:
		return false
	if not (Input.is_action_pressed("sprint") or _mobile_sprint_pressed):
		return false
	if _energy_value <= 0.0:
		return false

	_energy_value = maxf(0.0, _energy_value - (energy_drain_per_second * delta))
	return true


func _get_move_input_vector() -> Vector2:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("up"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_action_pressed("down"):
		input_dir.y += 1.0

	if input_dir.length_squared() <= 0.0001:
		input_dir = Input.get_vector("left", "right", "up", "down")

	if _mobile_controls_enabled and _mobile_move_vector.length_squared() > input_dir.length_squared():
		input_dir = _mobile_move_vector

	return input_dir


func _setup_mobile_controls_if_enabled() -> void:
	_mobile_controls_enabled = false

	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) == OK:
		_mobile_controls_enabled = bool(cfg.get_value("controls", "mobile_controls", false))

	if not _mobile_controls_enabled:
		return

	var btn_opacity := float(cfg.get_value("controls", "button_opacity", 0.85))

	_mobile_layer = CanvasLayer.new()
	_mobile_layer.layer = 120
	_mobile_layer.visible = true
	add_child(_mobile_layer)

	_mobile_btn_font = SystemFont.new()
	_mobile_btn_font.font_names = PackedStringArray(["Noto Sans", "Liberation Sans", "FreeSans", "sans-serif"])

	var viewport_size := get_viewport_rect().size
	_mobile_joystick_center = Vector2(90.0, viewport_size.y - 110.0)

	_mobile_joystick_base = Panel.new()
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.05, 0.07, 0.12, 0.58)
	base_style.corner_radius_top_left = int(_mobile_joystick_radius)
	base_style.corner_radius_top_right = int(_mobile_joystick_radius)
	base_style.corner_radius_bottom_left = int(_mobile_joystick_radius)
	base_style.corner_radius_bottom_right = int(_mobile_joystick_radius)
	_mobile_joystick_base.add_theme_stylebox_override("panel", base_style)
	_mobile_joystick_base.custom_minimum_size = Vector2(_mobile_joystick_radius * 2.0, _mobile_joystick_radius * 2.0)
	_mobile_joystick_base.size = Vector2(_mobile_joystick_radius * 2.0, _mobile_joystick_radius * 2.0)
	_mobile_joystick_base.position = _mobile_joystick_center - _mobile_joystick_base.size * 0.5
	_mobile_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_joystick_base.z_index = 200
	_mobile_layer.add_child(_mobile_joystick_base)

	_mobile_joystick_knob = Panel.new()
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(0.96, 0.96, 1.0, 0.95)
	knob_style.corner_radius_top_left = 23
	knob_style.corner_radius_top_right = 23
	knob_style.corner_radius_bottom_left = 23
	knob_style.corner_radius_bottom_right = 23
	_mobile_joystick_knob.add_theme_stylebox_override("panel", knob_style)
	_mobile_joystick_knob.custom_minimum_size = Vector2(46, 46)
	_mobile_joystick_knob.size = Vector2(46, 46)
	_mobile_joystick_knob.position = _mobile_joystick_center - _mobile_joystick_knob.size * 0.5
	_mobile_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_joystick_knob.z_index = 201
	_mobile_layer.add_child(_mobile_joystick_knob)

	var attack_d := 74.0
	var sprint_d := 64.0
	var heal_d := 56.0
	var small_d := 50.0
	var map_d := 46.0

	var ax := viewport_size.x - 80.0
	var ay := viewport_size.y - 90.0

	_add_mobile_action_button("\u2694", Vector2(ax, ay), attack_d, btn_opacity, func() -> void:
		_mobile_attack_pressed = true
	, func() -> void:
		_mobile_attack_pressed = false
	)

	_add_mobile_action_button("\u26A1", Vector2(ax - 90.0, ay - 48.0), sprint_d, btn_opacity, func() -> void:
		_mobile_sprint_pressed = true
	, func() -> void:
		_mobile_sprint_pressed = false
	)

	_add_mobile_action_button("\u2302", Vector2(viewport_size.x * 0.065, viewport_size.y * 0.10), map_d, btn_opacity, func() -> void:
		_mobile_map_pressed = true
	, func() -> void:
		_mobile_map_pressed = false
	)

	_add_mobile_tap_button("\u2665", Vector2(ax, ay - 86.0), heal_d, btn_opacity, Callable(self, "_use_health_potion"))

	var top_y := viewport_size.y * 0.15
	_add_mobile_tap_button("\u2726", Vector2(viewport_size.x - 160.0, top_y), small_d, btn_opacity, Callable(self, "_use_strength_potion"))
	_add_mobile_tap_button("\u2605", Vector2(viewport_size.x - 90.0, top_y), small_d, btn_opacity, Callable(self, "_use_energy_drink"))
	_add_mobile_tap_button("\u2600", Vector2(viewport_size.x - 230.0, top_y), small_d, btn_opacity, Callable(self, "_toggle_mobile_lamp"))
	_add_mobile_tap_button("E", Vector2(viewport_size.x - 300.0, top_y), small_d, btn_opacity, Callable(self, "_mobile_interact"))


func _add_mobile_action_button(label_text: String, center_pos: Vector2, diameter: float, opacity: float, on_press: Callable, on_release: Callable) -> void:
	if _mobile_layer == null:
		return

	var half := int(diameter * 0.5)
	var cr := int(diameter * 0.5)

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.18, 0.92 * opacity)
	style.border_color = Color(0.78, 0.60, 0.24, 0.6 * opacity)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = cr
	style.corner_radius_top_right = cr
	style.corner_radius_bottom_left = cr
	style.corner_radius_bottom_right = cr
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(diameter, diameter)
	panel.size = Vector2(diameter, diameter)
	panel.position = center_pos - Vector2(half, half)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 210
	panel.set_meta("base_r", 0.08)
	panel.set_meta("base_g", 0.10)
	panel.set_meta("base_b", 0.18)
	panel.set_meta("base_mult", 0.92)
	_mobile_layer.add_child(panel)
	_mobile_button_panels.append(panel)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_override("font", _mobile_btn_font)
	label.add_theme_font_size_override("font_size", int(diameter * 0.42))
	label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(diameter, diameter)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	_mobile_btn_infos.append({
		rect = Rect2(panel.position, panel.size),
		press = on_press,
		release = on_release,
		tap = Callable(),
		touch_id = -1
	})

	_update_panel_opacity(panel, opacity)


func _add_mobile_tap_button(label_text: String, center_pos: Vector2, diameter: float, opacity: float, on_tap: Callable) -> void:
	if _mobile_layer == null:
		return

	var half := int(diameter * 0.5)
	var cr := int(diameter * 0.5)

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.16, 0.90 * opacity)
	style.border_color = Color(0.78, 0.60, 0.24, 0.5 * opacity)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = cr
	style.corner_radius_top_right = cr
	style.corner_radius_bottom_left = cr
	style.corner_radius_bottom_right = cr
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(diameter, diameter)
	panel.size = Vector2(diameter, diameter)
	panel.position = center_pos - Vector2(half, half)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 210
	panel.set_meta("base_r", 0.07)
	panel.set_meta("base_g", 0.09)
	panel.set_meta("base_b", 0.16)
	panel.set_meta("base_mult", 0.90)
	_mobile_layer.add_child(panel)
	_mobile_button_panels.append(panel)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_override("font", _mobile_btn_font)
	label.add_theme_font_size_override("font_size", int(diameter * 0.38))
	label.add_theme_color_override("font_color", Color(0.91, 0.86, 0.75, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(diameter, diameter)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

	_mobile_btn_infos.append({
		rect = Rect2(panel.position, panel.size),
		press = Callable(),
		release = Callable(),
		tap = on_tap,
		touch_id = -1
	})

	_update_panel_opacity(panel, opacity)


func _update_panel_opacity(panel: Panel, opacity: float) -> void:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	var r := float(panel.get_meta("base_r"))
	var g := float(panel.get_meta("base_g"))
	var b := float(panel.get_meta("base_b"))
	var mult := float(panel.get_meta("base_mult"))
	style.bg_color = Color(r, g, b, mult * opacity)


func update_mobile_button_opacity(opacity: float) -> void:
	if _mobile_button_panels.is_empty():
		return
	_last_btn_opacity = opacity
	for panel in _mobile_button_panels:
		_update_panel_opacity(panel, opacity)
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) == OK:
		cfg.set_value("controls", "button_opacity", opacity)
		cfg.save(OPTIONS_PATH)


func _toggle_mobile_lamp() -> void:
	if lamp_control_unlocked and point_light:
		point_light.visible = not point_light.visible


func _mobile_interact() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	ev = InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = false
	Input.parse_input_event(ev)


func _process_mobile_buttons_event(event: InputEvent) -> bool:
	var event_pos: Vector2
	var pressed: bool
	var touch_id: int

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		event_pos = mb.position
		pressed = mb.pressed
		touch_id = 0
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		event_pos = touch.position
		pressed = touch.pressed
		touch_id = touch.index
	else:
		return false

	var handled := false

	if pressed:
		for info in _mobile_btn_infos:
			if info.touch_id == -1 and info.rect.has_point(event_pos):
				info.touch_id = touch_id
				if not info.tap.is_null():
					info.tap.call()
					handled = true
					break
				if not info.press.is_null():
					info.press.call()
					handled = true
					break
	else:
		for info in _mobile_btn_infos:
			if info.touch_id == touch_id:
				info.touch_id = -1
				if not info.release.is_null():
					info.release.call()
				handled = true
				break

	if handled:
		get_viewport().set_input_as_handled()

	return handled


func _update_mobile_joystick(screen_pos: Vector2) -> void:
	var offset := screen_pos - _mobile_joystick_center
	if offset.length() > _mobile_joystick_radius:
		offset = offset.normalized() * _mobile_joystick_radius
	_mobile_move_vector = offset / maxf(_mobile_joystick_radius, 1.0)
	if _mobile_joystick_knob != null:
		_mobile_joystick_knob.position = _mobile_joystick_center + offset - _mobile_joystick_knob.size * 0.5


func _reset_mobile_joystick() -> void:
	_mobile_move_vector = Vector2.ZERO
	if _mobile_joystick_knob != null:
		_mobile_joystick_knob.position = _mobile_joystick_center - _mobile_joystick_knob.size * 0.5


func _get_attack_facing_direction() -> Vector2:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0

	if input_dir == Vector2.ZERO:
		input_dir = Input.get_vector("left", "right", "up", "down")

	if input_dir.length_squared() > 0.0001:
		return input_dir.normalized()
	if last_dir.length_squared() > 0.0001:
		return last_dir.normalized()
	return Vector2.DOWN


func get_attack_anim(d: Vector2) -> String:
	if d.y < -0.5 and abs(d.x) < 0.5:
		return "atk-n"
	elif d.y > 0.5 and abs(d.x) < 0.5:
		return "atk-s"
	elif d.x > 0.5 and abs(d.y) < 0.5:
		return "atk-e"
	elif d.x < -0.5 and abs(d.y) < 0.5:
		return "atk-w"
	elif d.x > 0 and d.y < 0:
		return "atk-ne"
	elif d.x < 0 and d.y < 0:
		return "atk-nw"
	elif d.x > 0 and d.y > 0:
		return "atk-se"
	else:
		return "atk-sw"


# ---------- TILE DATA ----------

func get_stair_type() -> String:
	if tilemap == null:
		return ""
	
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
	var data: TileData = tilemap.get_cell_tile_data(0, cell)

	if data == null:
		return ""

	if data.has_custom_data("type"):
		var t = data.get_custom_data("type")
		if typeof(t) == TYPE_STRING:
			return t
	return ""


# ---------- BIAS SELECTOR ----------

func apply_stair_bias_velocity(vel: Vector2, stair_type: String) -> Vector2:
	var bias := 0.0
	var right_up := false

	match stair_type:
		"stair-r":
			bias = stair_bias
			right_up = true
		"stair-l":
			bias = stair_bias
			right_up = false
		"stair-r2":
			bias = stair_bias2
			right_up = true
		"stair-l2":
			bias = stair_bias2
			right_up = false
		_:
			return vel

	# only bias when mostly horizontal motion
	if abs(vel.x) > abs(vel.y):
		if right_up:
			vel.y += -bias if vel.x > 0 else bias
		else:
			vel.y += -bias if vel.x < 0 else bias

	return vel


# ---------- ANIMATION ----------

func update_animation(dir: Vector2):
	if _is_attacking:
		return

	var anim := ""

	if dir == Vector2.ZERO:
		anim = get_idle_anim(last_dir)
	else:
		anim = get_walk_anim(dir)

	if anim != current_anim:
		current_anim = anim
		if animated_sprite:
			animated_sprite.play(anim)
		else:
			push_error("AnimatedSprite2D is null, cannot play animation: ", anim)


func get_walk_anim(d: Vector2) -> String:
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


func get_idle_anim(d: Vector2) -> String:
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


func _separate_from_other_players() -> void:
	"""Push this player away from other players to prevent sticking."""
	var own_shape := collision_shape
	if own_shape == null or own_shape.disabled:
		return
	
	# Get all other players
	var all_players = get_tree().get_nodes_in_group("player")
	var own_collision_radius := 8.0
	
	for other_player in all_players:
		if other_player == self or not is_instance_valid(other_player):
			continue
		
		var other_pos = other_player.global_position
		var own_pos = global_position
		var distance = own_pos.distance_to(other_pos)
		var min_separation = own_collision_radius * 2.0
		
		# If overlapping, push apart
		if distance < min_separation and distance > 0.01:
			var push_dir = (own_pos - other_pos).normalized()
			var overlap = min_separation - distance
			var push_amount = overlap + 0.5  # Extra margin to ensure separation
			
			# Push both players apart (if the other is also a CharacterBody2D)
			global_position += push_dir * (push_amount * 0.5)
			if other_player is CharacterBody2D:
				other_player.global_position -= push_dir * (push_amount * 0.5)
