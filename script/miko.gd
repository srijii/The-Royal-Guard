extends CharacterBody2D

signal queen_ring_collected

# Finite state machine for Wizard AI.
enum State {
	WANDER,
	ANGRY,
	ATTACK,
}

@export var wander_radius: float = 96.0
@export var detection_radius: float = 180.0
@export var attack_range: float = 24.0
@export var move_speed_min: float = 62.0
@export var move_speed_max: float = 78.0
@export var attack_cooldown_min: float = 1.0
@export var attack_cooldown_max: float = 1.0
@export var attack_damage: int = 24
@export var attack_anim_time: float = 0.50
@export var attack_anim_fps: float = 3.0
@export var health: int = 260
@export var knockback_force_taken: float = 520.0
@export var knockback_decay: float = 520.0
@export var player_memory_time: float = 2.5
@export var idle_wait_min: float = 1.0
@export var idle_wait_max: float = 3.0
@export var avoid_turn_strength: float = 0.65
@export var stop_delay_time: float = 0.3
@export var float_horizontal_amplitude: float = 5.0
@export var float_vertical_amplitude: float = 9.0
@export var float_speed: float = 2.2

var spawn_position: Vector2
var current_state: State = State.WANDER
var target_position: Vector2
var player: Node2D = null
var last_direction: String = "s"

var move_speed: float = 120.0
var attack_cooldown: float = 0.25
var current_health: int = 120
var _wander_idle_time_left: float = 0.0
var _player_memory_left: float = 0.0
var _attack_cooldown_left: float = 0.0
var _attack_anim_left: float = 0.0
var _attack_hit_done := false
var _stop_delay_left: float = 0.0
var _combat_knockback_velocity: Vector2 = Vector2.ZERO
var _float_phase: float = 0.0
var _sprite_base_position: Vector2 = Vector2.ZERO
var _health_bar_control: Control = null
var _health_bar_base_position: Vector2 = Vector2.ZERO
var _drop_spawned := false
var _defeated := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var front_ray: RayCast2D = $"RayCast2D"
@onready var left_ray: RayCast2D = $"RayCast2D_left"
@onready var right_ray: RayCast2D = $"RayCast2D_right"
@onready var detection_area: Area2D = $DetectionArea
@onready var attack_area: Area2D = $AttackArea
@onready var attack_timer: Timer = $AttackCooldownTimer
var _health_bar_node: Range = null


func _ready() -> void:
	randomize()
	add_to_group("enemy")
	spawn_position = global_position
	target_position = spawn_position
	_choose_new_wander_target()
	# Randomize base stats from ranges.
	move_speed = randf_range(move_speed_min, move_speed_max)
	attack_cooldown = randf_range(attack_cooldown_min, attack_cooldown_max)
	current_health = health
	attack_timer.wait_time = attack_cooldown
	_resolve_health_bar_node()
	_refresh_health_bar()
	if _health_bar_node is Control:
		_health_bar_control = _health_bar_node as Control
		_health_bar_base_position = _health_bar_control.position
	
	# Area signals are optional for behavior, but useful for quick target acquisition.
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	attack_area.body_entered.connect(_on_attack_body_entered)
	attack_area.body_exited.connect(_on_attack_body_exited)
	attack_timer.timeout.connect(_on_attack_cooldown_timeout)
	attack_timer.one_shot = true
	
	# Match Area2D radii with exported gameplay values.
	_set_area_radii()
	_configure_attack_animation_fps()

	if animated_sprite != null:
		_sprite_base_position = animated_sprite.position
		_float_phase = randf() * TAU


func _physics_process(delta: float) -> void:
	if _defeated:
		velocity = Vector2.ZERO
		return

	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if _attack_anim_left > 0.0:
		_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	if _stop_delay_left > 0.0:
		_stop_delay_left = maxf(0.0, _stop_delay_left - delta)
	if _combat_knockback_velocity.length() > 0.01:
		_combat_knockback_velocity = _combat_knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)

	_refresh_player_reference()
	_update_player_memory(delta)
	_update_state()
	
	match current_state:
		State.ATTACK:
			_process_attack_state(delta)
		State.ANGRY:
			_process_angry_state(delta)
		State.WANDER:
			_process_wander_state(delta)

	velocity += _combat_knockback_velocity
	
	move_and_slide()
	_handle_collision_reroute()
	_update_floating_effect(delta)


func _update_floating_effect(delta: float) -> void:
	if animated_sprite == null:
		return

	_float_phase += delta * float_speed
	var x_offset := cos(_float_phase) * float_horizontal_amplitude
	var y_offset := sin(_float_phase) * float_vertical_amplitude
	# Add a subtle second harmonic for a more magical hover feel.
	y_offset += sin(_float_phase * 2.0) * 1.6
	var float_offset := Vector2(x_offset, y_offset)
	animated_sprite.position = _sprite_base_position + float_offset

	# Keep health bar floating in sync with the warden.
	if _health_bar_control != null:
		_health_bar_control.position = _health_bar_base_position + float_offset


func _handle_collision_reroute() -> void:
	if get_slide_collision_count() <= 0:
		return

	# In ATTACK we intentionally hold position; don't reroute there.
	if current_state == State.ATTACK:
		return

	# Use collision normal to turn away from obstacle quickly.
	var collision := get_slide_collision(0)
	if collision == null:
		return

	var normal: Vector2 = collision.get_normal()
	if normal.length() < 0.001:
		return

	var away_dir := normal.normalized()

	if current_state == State.WANDER:
		# Pick a new nearby target away from the obstacle.
		var reroute_dist := randf_range(wander_radius * 0.25, wander_radius * 0.6)
		target_position = global_position + away_dir * reroute_dist
		_wander_idle_time_left = 0.0
		velocity = away_dir * move_speed
		_update_direction_from_vector(velocity)
		_play_walk_animation()
	elif current_state == State.ANGRY:
		# Keep chase behavior but instantly steer away from the blocking surface.
		velocity = away_dir * move_speed
		_update_direction_from_vector(velocity)
		_play_walk_animation()


func _set_area_radii() -> void:
	var detect_shape := detection_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if detect_shape and detect_shape.shape is CircleShape2D:
		(detect_shape.shape as CircleShape2D).radius = detection_radius

	var atk_shape := attack_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if atk_shape and atk_shape.shape is CircleShape2D:
		(atk_shape.shape as CircleShape2D).radius = attack_range


func _refresh_player_reference() -> void:
	if player != null and is_instance_valid(player):
		return

	for body in detection_area.get_overlapping_bodies():
		if _is_player(body):
			player = body as Node2D
			return

	# Fallbacks for common setups.
	var group_players := get_tree().get_nodes_in_group("player")
	if group_players.size() > 0:
		player = group_players[0] as Node2D
		return

	var p := get_node_or_null("/root/Player")
	if p is Node2D:
		player = p


func _update_player_memory(delta: float) -> void:
	if _player_in_detection_range():
		_player_memory_left = player_memory_time
	else:
		_player_memory_left = maxf(0.0, _player_memory_left - delta)


func _update_state() -> void:
	# Priority: ATTACK > ANGRY > WANDER
	if _can_attack_player():
		current_state = State.ATTACK
		return

	if _should_chase_player():
		current_state = State.ANGRY
		return

	current_state = State.WANDER


func _process_wander_state(delta: float) -> void:
	if _wander_idle_time_left > 0.0:
		_wander_idle_time_left = maxf(0.0, _wander_idle_time_left - delta)
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 6.0)
		_play_idle_animation()
		if _wander_idle_time_left <= 0.0:
			_choose_new_wander_target()
			_stop_delay_left = stop_delay_time
		return

	var to_target := target_position - global_position
	if to_target.length() <= 8.0:
		_wander_idle_time_left = randf_range(idle_wait_min, idle_wait_max)
		velocity = Vector2.ZERO
		_play_idle_animation()
		_stop_delay_left = stop_delay_time
		return

	# Don't resume movement until stop delay expires.
	if _stop_delay_left > 0.0:
		velocity = Vector2.ZERO
		_play_idle_animation()
		return

	var desired := to_target.normalized()
	desired = _avoid_obstacles(desired)
	velocity = desired * move_speed
	_update_direction_from_vector(velocity)
	_play_walk_animation()


func _process_angry_state(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 6.0)
		_play_idle_animation()
		return

	var to_player := player.global_position - global_position
	if to_player.length() < 0.001:
		velocity = Vector2.ZERO
		_play_idle_animation()
		_stop_delay_left = stop_delay_time
		return

	# Don't chase until stop delay expires.
	if _stop_delay_left > 0.0:
		velocity = Vector2.ZERO
		_play_idle_animation()
		return

	var desired := to_player.normalized()
	desired = _avoid_obstacles(desired)
	velocity = desired * move_speed
	_update_direction_from_vector(velocity)
	_play_walk_animation()


func _process_attack_state(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		velocity = Vector2.ZERO
		if _attack_anim_left > 0.0:
			_play_attack_animation(false)
		else:
			_play_idle_animation()
		return

	velocity = Vector2.ZERO
	var to_player := player.global_position - global_position
	if to_player.length() > 0.001:
		_update_direction_from_vector(to_player.normalized())

	if _attack_anim_left > 0.0:
		_play_attack_animation(false)
		_try_apply_attack_on_last_frame()
		return

	var in_attack_window := _player_in_attack_range() and _has_line_of_sight_to_player()
	if in_attack_window:
		_play_idle_animation()
		if _attack_cooldown_left <= 0.0 and _attack_anim_left <= 0.0:
			_perform_attack()
	else:
		# Safety fallback; normally state priority should switch out of ATTACK.
		_play_idle_animation()


func _perform_attack() -> void:
	_attack_cooldown_left = attack_cooldown
	_attack_anim_left = _get_attack_cycle_duration(last_direction)
	_attack_hit_done = false
	attack_timer.start(attack_cooldown)
	_play_attack_animation(true)


func _configure_attack_animation_fps() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var directions: PackedStringArray = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	for dir in directions:
		var anim_name: String = "atk-" + dir
		if animated_sprite.sprite_frames.has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_speed(anim_name, attack_anim_fps)


func _get_attack_cycle_duration(dir: String) -> float:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return attack_anim_time

	var anim_name: String = "atk-" + dir
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		anim_name = "atk-s"
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return attack_anim_time

	var frames := animated_sprite.sprite_frames.get_frame_count(anim_name)
	var fps := animated_sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		fps = attack_anim_fps
	if fps <= 0.0 or frames <= 0:
		return attack_anim_time
	return float(frames) / fps


func _try_apply_attack_on_last_frame() -> void:
	if _attack_hit_done:
		return
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var anim_name: String = String(animated_sprite.animation)
	if not anim_name.begins_with("atk-"):
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return

	var frame_count := animated_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return

	if animated_sprite.frame >= frame_count - 1:
		_attack_hit_done = true
		_apply_attack_hit_effects()


func _apply_attack_hit_effects() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _player_in_attack_range() or not _has_line_of_sight_to_player():
		return

	# Wait for sweep timing, then apply impact effects and damage together.
	var damage_timer := create_tween()
	damage_timer.tween_callback(func() -> void:
		if player == null or not is_instance_valid(player):
			return
		if not _player_in_attack_range() or not _has_line_of_sight_to_player():
			return
		_spawn_shockwave(player.global_position)
		if player.has_method("take_damage"):
			player.call("take_damage", attack_damage)
		if player.has_method("apply_combat_knockback"):
			player.call("apply_combat_knockback", global_position, 430.0)
	).set_delay(0.2)


func _spawn_shockwave(_shockwave_target: Vector2) -> void:
	var fx_root := get_tree().current_scene
	if fx_root == null:
		fx_root = get_tree().root

	var pulse := Polygon2D.new()
	pulse.polygon = PackedVector2Array([
		Vector2(0.0, -7.0),
		Vector2(12.0, 0.0),
		Vector2(0.0, 7.0),
		Vector2(-12.0, 0.0)
	])
	pulse.color = Color(0.6, 0.9, 0.7, 0.95)
	pulse.global_position = global_position
	fx_root.add_child(pulse)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "global_position", target_position, 0.20)
	tween.tween_property(pulse, "scale", Vector2(1.8, 1.8), 0.20).from(Vector2.ONE)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.20)
	tween.finished.connect(func() -> void:
		if is_instance_valid(pulse):
			pulse.queue_free()
	)


func _choose_new_wander_target() -> void:
	var random_angle := randf() * TAU
	# Pick nearby destinations so idle/wander stays local.
	var random_dist := randf_range(wander_radius * 0.25, wander_radius)
	var offset := Vector2.RIGHT.rotated(random_angle) * random_dist
	target_position = global_position + offset


func _avoid_obstacles(base_dir: Vector2) -> Vector2:
	if base_dir.length() < 0.001:
		return base_dir

	var move_dir := base_dir.normalized()
	front_ray.target_position = move_dir * maxf(front_ray.target_position.length(), 18.0)
	front_ray.force_raycast_update()
	left_ray.force_raycast_update()
	right_ray.force_raycast_update()

	var front_blocked := front_ray.is_colliding()
	if not front_blocked:
		return move_dir

	# If front is blocked, prefer side with no collision; else rotate away.
	var left_blocked := left_ray.is_colliding()
	var right_blocked := right_ray.is_colliding()
	if left_blocked and not right_blocked:
		return move_dir.rotated(deg_to_rad(35.0))
	if right_blocked and not left_blocked:
		return move_dir.rotated(deg_to_rad(-35.0))
	if not left_blocked:
		return move_dir.rotated(deg_to_rad(-45.0 * avoid_turn_strength))
	if not right_blocked:
		return move_dir.rotated(deg_to_rad(45.0 * avoid_turn_strength))

	# All blocked, briefly back off.
	return -move_dir


func _can_attack_player() -> bool:
	return _player_in_attack_range() and _has_line_of_sight_to_player()


func _should_chase_player() -> bool:
	if _player_in_detection_range():
		return true
	return _player_memory_left > 0.0 and player != null and is_instance_valid(player)


func _player_in_detection_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= detection_radius


func _player_in_attack_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= attack_range


func _has_line_of_sight_to_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false

	var to_player := player.global_position - global_position
	if to_player.length() < 0.001:
		return true

	front_ray.target_position = to_player
	front_ray.force_raycast_update()
	if not front_ray.is_colliding():
		return true

	var collider := front_ray.get_collider()
	return collider == player


func _update_direction_from_vector(v: Vector2) -> void:
	if v.length() < 0.001:
		return
	last_direction = _vector_to_dir_name(v)


func _vector_to_dir_name(v: Vector2) -> String:
	var dir := v.normalized()
	var angle := atan2(dir.y, dir.x)
	var octant := int(round(angle / (PI / 4.0)))
	match octant:
		-4, 4:
			return "w"
		-3:
			return "nw"
		-2:
			return "n"
		-1:
			return "ne"
		0:
			return "e"
		1:
			return "se"
		2:
			return "s"
		3:
			return "sw"
	return "s"


func _play_walk_animation() -> void:
	_play_directional_with_fallback("walk", last_direction)


func _play_idle_animation() -> void:
	_play_directional_with_fallback("idle", last_direction)


func _play_attack_animation(force_restart := false) -> void:
	_play_directional_with_fallback("atk", last_direction, force_restart)


func _play_directional_with_fallback(prefix: String, dir: String, force_restart := false) -> void:
	if animated_sprite.sprite_frames == null:
		return

	var order := _direction_fallback_order(dir)
	for candidate_dir in order:
		var anim_name := prefix + "-" + candidate_dir
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if force_restart or animated_sprite.animation != anim_name or not animated_sprite.is_playing():
				animated_sprite.play(anim_name)
			return

	# Absolute last fallback.
	var hard_fallback := prefix + "-s"
	if animated_sprite.sprite_frames.has_animation(hard_fallback):
		if force_restart or animated_sprite.animation != hard_fallback or not animated_sprite.is_playing():
			animated_sprite.play(hard_fallback)


func _direction_fallback_order(dir: String) -> Array[String]:
	match dir:
		"n":
			return ["n", "ne", "nw", "e", "w", "s"]
		"ne":
			return ["ne", "n", "e", "se", "nw", "s", "w"]
		"e":
			return ["e", "ne", "se", "n", "s", "w"]
		"se":
			return ["se", "s", "e", "sw", "ne", "w", "n"]
		"s":
			return ["s", "se", "sw", "e", "w", "n"]
		"sw":
			return ["sw", "s", "w", "se", "nw", "e", "n"]
		"w":
			return ["w", "nw", "sw", "n", "s", "e"]
		"nw":
			return ["nw", "n", "w", "ne", "sw", "e", "s"]
		_:
			return ["s", "se", "sw", "e", "w", "n", "ne", "nw"]


func _play_if_exists(anim_name: String) -> void:
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name:
			animated_sprite.play(anim_name)
	else:
		# Fallback to south variants to avoid runtime errors if any animation is missing.
		var fallback := "idle-s"
		if anim_name.begins_with("walk-"):
			fallback = "walk-s"
		elif anim_name.begins_with("atk-"):
			fallback = "atk-s"
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(fallback):
			if animated_sprite.animation != fallback:
				animated_sprite.play(fallback)


func _is_player(node: Node) -> bool:
	if node == null:
		return false
	if node.has_method("is_player"):
		return bool(node.call("is_player"))
	return node.is_in_group("player") or node.name.to_lower() == "player"


func _on_detection_body_entered(body: Node) -> void:
	if _is_player(body):
		player = body as Node2D
		_player_memory_left = player_memory_time


func _on_detection_body_exited(body: Node) -> void:
	if body == player:
		# Keep memory timer running, then return to wander automatically.
		_player_memory_left = player_memory_time


func _on_attack_body_entered(body: Node) -> void:
	if _is_player(body):
		player = body as Node2D


func _on_attack_body_exited(body: Node) -> void:
	if body == player:
		# State logic will demote to angry/wander based on distance + memory.
		pass


func _on_attack_cooldown_timeout() -> void:
	_attack_cooldown_left = 0.0


func take_damage(amount: int) -> void:
	if _defeated:
		return
	Helpers.spawn_blood_effect(global_position)
	Helpers.spawn_blood_stain(global_position)
	current_health = max(0, current_health - amount)
	_refresh_health_bar()
	if current_health <= 0:
		_defeated = true
		_drop_ring_loot()
		_enter_defeated_state()


func _enter_defeated_state() -> void:
	remove_from_group("enemy")
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_process(false)

	if detection_area != null:
		detection_area.monitoring = false
		detection_area.monitorable = false
	if attack_area != null:
		attack_area.monitoring = false
		attack_area.monitorable = false

	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)

	if animated_sprite != null:
		animated_sprite.visible = false
	if _health_bar_control != null:
		_health_bar_control.visible = false


func _drop_ring_loot() -> void:
	if _drop_spawned:
		return
	_drop_spawned = true
	var tint := Color(0.92, 0.84, 0.28, 1.0)

	var pickup := Area2D.new()
	pickup.name = "QueensRingDrop"
	pickup.global_position = global_position
	pickup.monitoring = true
	pickup.monitorable = true
	pickup.z_as_relative = false
	pickup.z_index = 100
	pickup.y_sort_enabled = false

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	pickup.add_child(shape)

	var ring_sprite := Sprite2D.new()
	ring_sprite.texture = _build_ring_drop_texture(tint)
	ring_sprite.scale = Vector2(0.9, 0.9)
	ring_sprite.z_as_relative = false
	ring_sprite.z_index = 102
	pickup.add_child(ring_sprite)

	pickup.body_entered.connect(func(body: Node) -> void:
		if body == null or not is_instance_valid(body):
			return
		if pickup == null or not is_instance_valid(pickup):
			return
		if _is_player(body):
			var tree := pickup.get_tree()
			if tree != null:
				tree.call_group("final_boss_controller", "_on_queen_ring_collected")
			pickup.queue_free()
	)

	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(pickup)
	call_deferred("_check_ring_auto_collect", pickup)

	# Small float animation to make pickup feel alive.
	var tween := pickup.create_tween()
	tween.set_loops()
	tween.tween_property(pickup, "position:y", pickup.position.y - 5.0, 0.45)
	tween.tween_property(pickup, "position:y", pickup.position.y + 5.0, 0.45)


func _check_ring_auto_collect(pickup: Area2D) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	await get_tree().physics_frame
	if pickup == null or not is_instance_valid(pickup):
		return
	for body in pickup.get_overlapping_bodies():
		if _is_player(body):
			var tree := pickup.get_tree()
			if tree != null:
				tree.call_group("final_boss_controller", "_on_queen_ring_collected")
			pickup.queue_free()
			return


func _build_ring_drop_texture(tint: Color) -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var ring_outer := Color(0.98, 0.92, 0.38, 1.0)
	var ring_inner := Color(0.58, 0.48, 0.16, 0.0)

	for y in range(24):
		for x in range(24):
			var dx := float(x) - 12.0
			var dy := float(y) - 12.0
			var d2 := dx * dx + dy * dy
			if d2 <= 49.0 and d2 >= 24.0:
				image.set_pixel(x, y, ring_outer)
			elif d2 < 24.0:
				image.set_pixel(x, y, ring_inner)

	# Gem highlight on top.
	for y in range(2, 7):
		for x in range(10, 14):
			image.set_pixel(x, y, tint)

	return ImageTexture.create_from_image(image)


func apply_combat_knockback(from_position: Vector2, force := knockback_force_taken) -> void:
	var away := global_position - from_position
	if away.length_squared() < 0.0001:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	away = away.normalized()
	_combat_knockback_velocity += away * force


func _resolve_health_bar_node() -> void:
	# Supports user-added bars such as HealthBar/healthBar/WardenHealthBar,
	# including TextureProgressBar while preserving existing textures/style.
	var candidates := [
		"HealthBar",
		"healthBar",
		"WardenHealthBar",
		"WardenHP",
		"HPBar",
	]
	for path in candidates:
		var n := get_node_or_null(path)
		if n is Range:
			_health_bar_node = n as Range
			return

	_health_bar_node = _find_health_bar_recursive(self)


func _find_health_bar_recursive(root: Node) -> Range:
	for child in root.get_children():
		if child is Range:
			var n := String(child.name).to_lower()
			if n.contains("health") or n.contains("hp") or n.contains("bar"):
				return child as Range
		var nested := _find_health_bar_recursive(child)
		if nested != null:
			return nested
	return null


func _refresh_health_bar() -> void:
	if _health_bar_node == null:
		return
	_health_bar_node.min_value = 0.0
	_health_bar_node.max_value = float(max(health, 1))
	_health_bar_node.value = float(current_health)
	if _health_bar_node is CanvasItem:
		(_health_bar_node as CanvasItem).visible = true
