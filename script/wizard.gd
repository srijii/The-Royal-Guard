extends CharacterBody2D

# Finite state machine for Wizard AI.
enum State {
	WANDER,
	ANGRY,
	ATTACK,
}

@export var wander_radius: float = 96.0
@export var detection_radius: float = 300.0
@export var attack_range: float = 160.0
@export var move_speed_min: float = 90.0
@export var move_speed_max: float = 110.0
@export var attack_cooldown_min: float = 1.3
@export var attack_cooldown_max: float = 1.8
@export var attack_damage: int = 38
@export var attack_anim_time: float = 0.45
@export var health: int = 350
@export var knockback_force_taken: float = 600.0
@export var knockback_decay: float = 600.0
@export var player_knockback_force: float = 500.0
@export var player_memory_time: float = 4.0
@export var idle_wait_min: float = 1.0
@export var idle_wait_max: float = 3.0
@export var avoid_turn_strength: float = 0.65
@export var stop_delay_time: float = 0.3
@export var wander_unstuck_seconds: float = 0.6
@export var wander_phase_seconds: float = 0.4
@export var float_horizontal_amplitude: float = 6.0
@export var float_vertical_amplitude: float = 11.0
@export var float_speed: float = 2.8

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
var _stop_delay_left: float = 0.0
var _combat_knockback_velocity: Vector2 = Vector2.ZERO
var _float_phase: float = 0.0
var _sprite_base_position: Vector2 = Vector2.ZERO
var _health_bar_control: Control = null
var _health_bar_base_position: Vector2 = Vector2.ZERO
var _drop_spawned := false
var _wander_stuck_time := 0.0
var _phase_time_left := 0.0
var _base_collision_layer := 0
var _base_collision_mask := 0

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

	if animated_sprite != null:
		_sprite_base_position = animated_sprite.position
		_float_phase = randf() * TAU

	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
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
	
	if is_inside_tree():
		var moved_distance := _get_moved_distance(velocity, delta)
		move_and_slide()
		_update_wander_unstuck(delta, moved_distance)
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


func _get_moved_distance(velocity_vec: Vector2, delta: float) -> float:
	return velocity_vec.length() * delta


func _update_wander_unstuck(delta: float, moved_distance: float) -> void:
	if current_state != State.WANDER:
		_wander_stuck_time = 0.0
		_phase_time_left = 0.0
		_set_collision_phase(false)
		return

	if _phase_time_left > 0.0:
		_phase_time_left = maxf(0.0, _phase_time_left - delta)
		if _phase_time_left <= 0.0:
			_set_collision_phase(false)

	if _wander_idle_time_left > 0.0 or _stop_delay_left > 0.0:
		_wander_stuck_time = 0.0
		return

	var trying_to_move := velocity.length() > 12.0
	if trying_to_move and moved_distance < 0.8:
		_wander_stuck_time += delta
	else:
		_wander_stuck_time = 0.0

	if _wander_stuck_time < wander_unstuck_seconds:
		return

	_wander_stuck_time = 0.0
	_phase_time_left = maxf(0.05, wander_phase_seconds)
	_set_collision_phase(true)
	_choose_new_wander_target()
	var to_target := target_position - global_position
	if to_target.length() > 0.01:
		velocity = to_target.normalized() * move_speed
		_update_direction_from_vector(velocity)
		_play_walk_animation()


func _set_collision_phase(enabled: bool) -> void:
	if enabled:
		collision_layer = 0
		collision_mask = 0
		return

	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask


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
		_play_idle_animation()
		return

	velocity = Vector2.ZERO
	var to_player := player.global_position - global_position
	if to_player.length() > 0.001:
		_update_direction_from_vector(to_player.normalized())

	var in_attack_window := _player_in_attack_range() and _has_line_of_sight_to_player()
	if in_attack_window:
		if _attack_anim_left > 0.0:
			_play_attack_animation()
		else:
			_play_idle_animation()
		if _attack_cooldown_left <= 0.0 and _attack_anim_left <= 0.0:
			_perform_attack()
	else:
		# Safety fallback; normally state priority should switch out of ATTACK.
		_play_idle_animation()


func _perform_attack() -> void:
	_attack_cooldown_left = attack_cooldown
	_attack_anim_left = attack_anim_time
	attack_timer.start(attack_cooldown)

	if player == null or not is_instance_valid(player):
		return

	_spawn_shockwave(player.global_position)


func _spawn_shockwave(shockwave_target: Vector2) -> void:
	if not is_inside_tree():
		return
	var fx_root := get_tree().current_scene
	if fx_root == null:
		fx_root = get_tree().root

	var distance_to_target := global_position.distance_to(shockwave_target)
	var travel_time := 0.7

	var pulse := Polygon2D.new()
	var points := PackedVector2Array()
	var segments := 16
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle) * 6.0, sin(angle) * 6.0))
	pulse.polygon = points
	pulse.color = Color(0.85, 0.4, 1.0, 1.0)
	pulse.global_position = global_position
	fx_root.add_child(pulse)

	var trail := Line2D.new()
	trail.width = 3.0
	trail.default_color = Color(0.75, 0.35, 0.95, 0.6)
	trail.points = PackedVector2Array([global_position, global_position])
	fx_root.add_child(trail)

	var target_ref: WeakRef = weakref(player) if player != null else null
	var start_pos := global_position
	var captured_damage := attack_damage
	var captured_knockback := player_knockback_force

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "global_position", shockwave_target, travel_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_property(pulse, "scale", Vector2(1.2, 1.2), travel_time).from(Vector2.ONE)
	tween.tween_property(trail, "modulate:a", 0.0, travel_time)
	tween.chain().tween_callback(func() -> void:
		trail.queue_free()
		pulse.polygon = PackedVector2Array()
		var explosion_points := PackedVector2Array()
		var explosion_segments := 24
		for i in range(explosion_segments):
			var angle := (float(i) / float(explosion_segments)) * TAU
			explosion_points.append(Vector2(cos(angle) * 8.0, sin(angle) * 8.0))
		pulse.polygon = explosion_points
		pulse.color = Color(1.0, 0.6, 1.0, 1.0)
		pulse.scale = Vector2(1.0, 1.0)
		var explode_tween := create_tween()
		explode_tween.set_parallel(true)
		explode_tween.tween_property(pulse, "scale", Vector2(6.0, 6.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		explode_tween.tween_property(pulse, "modulate:a", 0.0, 0.35).set_delay(0.1)
		explode_tween.tween_callback(_on_shockwave_hit.bind(target_ref, shockwave_target, distance_to_target, start_pos, captured_damage, captured_knockback, pulse)).set_delay(0.05)
	)


func _on_shockwave_hit(target_ref: WeakRef, shockwave_target: Vector2, distance_to_target: float, start_pos: Vector2, captured_damage: int, captured_knockback: float, pulse: Polygon2D) -> void:
	if target_ref != null:
		var p: Object = target_ref.get_ref()
		if p != null and is_instance_valid(p):
			var player_dist: float = (p as Node2D).global_position.distance_to(shockwave_target)
			if player_dist <= 60.0:
				var dist_ratio := clampf(distance_to_target / attack_range, 0.0, 1.0)
				var scaled_damage := int(round(captured_damage * (0.3 + 0.7 * dist_ratio)))
				var scaled_knockback := captured_knockback * (0.5 + 0.5 * dist_ratio)
				if p.has_method("take_damage"):
					p.call("take_damage", scaled_damage)
				if p.has_method("apply_combat_knockback"):
					p.call("apply_combat_knockback", start_pos, scaled_knockback)
	if pulse != null and is_instance_valid(pulse):
		pulse.queue_free()


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


func _play_attack_animation() -> void:
	_play_directional_with_fallback("atk", last_direction)


func _play_directional_with_fallback(prefix: String, dir: String) -> void:
	if animated_sprite.sprite_frames == null:
		return

	var order := _direction_fallback_order(dir)
	for candidate_dir in order:
		var anim_name := prefix + "-" + candidate_dir
		if animated_sprite.sprite_frames.has_animation(anim_name):
			if animated_sprite.animation != anim_name:
				animated_sprite.play(anim_name)
			return

	# Absolute last fallback.
	var hard_fallback := prefix + "-s"
	if animated_sprite.sprite_frames.has_animation(hard_fallback):
		if animated_sprite.animation != hard_fallback:
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
	Helpers.spawn_blood_effect(global_position)
	Helpers.spawn_blood_stain(global_position)
	current_health = max(0, current_health - amount)
	_refresh_health_bar()
	if current_health <= 0:
		_drop_key_loot()
		queue_free()


func _drop_key_loot() -> void:
	if _drop_spawned:
		return
	_drop_spawned = true
	var tint := Color(0.95, 0.84, 0.24, 1.0)

	var pickup := Area2D.new()
	pickup.name = "WizardKeyDrop"
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

	var key_sprite := Sprite2D.new()
	key_sprite.texture = _build_key_drop_texture(tint)
	key_sprite.scale = Vector2(0.72, 0.72)
	key_sprite.z_as_relative = false
	key_sprite.z_index = 102
	pickup.add_child(key_sprite)

	var pickup_ref: WeakRef = weakref(pickup)
	pickup.body_entered.connect(_on_key_pickup_body_entered.bind(pickup_ref))

	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(pickup)

	# Small float animation to make pickup feel alive.
	var tween := pickup.create_tween()
	tween.set_loops()
	tween.tween_property(pickup, "position:y", pickup.position.y - 5.0, 0.45)
	tween.tween_property(pickup, "position:y", pickup.position.y + 5.0, 0.45)


func _build_key_drop_texture(tint: Color) -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var metal := Color(0.98, 0.93, 0.55, 1.0)

	for y in range(4, 12):
		for x in range(4, 12):
			var dx := float(x) - 8.0
			var dy := float(y) - 8.0
			var d2 := dx * dx + dy * dy
			if d2 <= 16.0 and d2 >= 6.0:
				image.set_pixel(x, y, metal)

	for y in range(7, 10):
		for x in range(9, 19):
			image.set_pixel(x, y, tint)

	for y in range(10, 14):
		image.set_pixel(15, y, tint)
	for y in range(9, 12):
		image.set_pixel(18, y, tint)

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
		"WizardHealthBar",
		"WizardHP",
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


func _on_key_pickup_body_entered(body: Node, pickup_ref: WeakRef) -> void:
	var pickup := pickup_ref.get_ref() as Area2D
	if pickup == null or not is_instance_valid(pickup):
		return
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("add_wizard_key"):
		body.call("add_wizard_key")
		pickup.queue_free()
