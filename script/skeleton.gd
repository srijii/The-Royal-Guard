
extends CharacterBody2D

func _is_player_target(body: Node) -> bool:
	# Adjust this logic as needed for your player node
	return body != null and body.has_method("is_player") and body.is_player()

signal ring_stolen

var health = 300
var current_health = health
@onready var healthBar = $healthBar
@onready var wander_controller = $WanderController
@export var auto_regen_below_percent := 50.0
@export var auto_regen_per_second := 22.0
@export var move_speed := 95.0
@export var attack_range := 38.0
@export var attack_cooldown := 1.0
@export var attack_throw_force := 700.0
@export var attack_throw_duration := 0.8
@export var wander_target_reached_distance := 10.0
@export var chase_probe_distance := 34.0
@export var chase_detour_scan_rays := 9
@export var chase_detour_scan_angle_degrees := 120.0

var dir = Vector2.RIGHT
var start_position: Vector2
enum { IDLE, REACT, WALK, DIE, ATTACK, HIT, NEW_DIR }
var current_state = IDLE

var is_roaming = true
var is_attacking = false
var is_dead = false

var player = null
var queen = null
var _attack_cooldown_left := 0.0
var _attack_in_progress := false
var _target_locked := false
var _instant_kill_target := false
var _has_hit_queen := false
var _forced_player_aggro := false

var _pass_through_bob_phase := 0.0
var _sprite_base_position := Vector2.ZERO

@export var retarget_interval := 0.3
@export var teleport_if_player_farther_than := 260.0
@export var teleport_player_offset := Vector2(40, 0)

var _retarget_timer := 0.0

func _get_player_stats() -> Node:
	return get_node_or_null("/root/PlayerStats")



func _is_target_alive(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("is_alive"):
		return bool(target.call("is_alive"))
	if "is_alive" in target:
		return bool(target.is_alive)
	return true


func _add_shooting_progress(amount: float) -> void:
	var stats := _get_player_stats()
	# _try_attack_target(target)  # Removed because 'target' is not defined in this scope
	stats.call("shooting_level", amount)


func _get_arrow_damage() -> float:
	var stats := _get_player_stats()
	if stats == null:
		return 100.0
	var shooting := float(stats.get("shooting"))
	var max_level := maxf(1.0, float(stats.get("max_shooting_level")))
	return 100.0 * shooting / max_level

func _ready():
	randomize()
	add_to_group("enemy")
	start_position = position
	healthBar.value = current_health
	_sprite_base_position = $AnimatedSprite2D.position
	# Find and set the player as initial target
	var root = get_tree().root
	for child in root.get_children():
		if child.has_method("is_player"):
			player = child
			break
		var player_node = child.find_child("CharacterBody2D", true, false)
		if player_node and player_node.has_method("is_player"):
			player = player_node
			break
	# If no player found, try common player node names
	if player == null:
		var player_nodes = get_tree().get_nodes_in_group("player")
		if player_nodes.size() > 0:
			player = player_nodes[0]
	if player == null:
		player = get_node_or_null("/root/Player")
	get_state()


func get_state():
	var r = randi_range(0, 2)
	match r:
		0:
			current_state = IDLE
		1:
			current_state = REACT
		2:
			current_state = WALK
		#3:
		#	current_state = NEW_DIR


func _process(delta):
	if is_dead:
		return

	_update_auto_regen(delta)

	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)

	# Retarget every 0.3 seconds
	_retarget_timer += delta
	if _retarget_timer >= retarget_interval:
		_retarget_timer = 0.0
		_retarget_to_nearest()

	var target := _current_target()
	if target == player:
		_process_chase_and_attack_player(delta)
	elif target == queen:
		_process_chase_and_attack_queen(delta)
	else:
		_process_wander(delta)


func _current_target() -> Node:
	var player_alive := player != null and _is_target_alive(player)
	var queen_alive := queen != null and _is_target_alive(queen)

	if _forced_player_aggro:
		if player_alive:
			return player
		return null

	if not player_alive and not queen_alive:
		return null

	# Always prioritize the player if alive, only target queen if player is dead
	if player_alive:
		return player
	elif queen_alive:
		return queen
	else:
		return null


func _retarget_to_nearest() -> void:
	# Always track both targets dynamically - skeleton targets nearest regardless of ring status
	var next_target := _current_target()
	# Keep both player and queen alive for retargeting
	if next_target == null:
		player = null
		queen = null


func _process_chase_and_attack_queen(delta: float) -> void:
	if queen == null or not _is_target_alive(queen):
		_reset_pass_through_bob(delta)
		return

	var to_queen: Vector2 = queen.global_position - global_position
	var dist: float = to_queen.length()
	if dist <= 0.001:
		to_queen = Vector2.RIGHT
	var move_dir := to_queen.normalized()

	if to_queen.x != 0.0:
		$AnimatedSprite2D.flip_h = to_queen.x < 0.0

	# Chase the queen
	is_attacking = false
	current_state = WALK
	$AnimatedSprite2D.play("walk")
	if _is_direction_blocked(move_dir):
		move_dir = _find_detour_direction(move_dir)
	var chase_vel: Vector2 = move_dir * move_speed
	velocity = velocity.move_toward(chase_vel, move_speed * delta * 5.0)
	move_and_slide()

	if dist <= attack_range:
		_try_attack_queen()

	_reset_pass_through_bob(delta)


func _process_chase_and_attack_player(delta: float) -> void:
	if player == null or not _is_target_alive(player):
		_reset_pass_through_bob(delta)
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist <= 0.001:
		to_player = Vector2.RIGHT
	var move_dir := to_player.normalized()

	if to_player.x != 0.0:
		$AnimatedSprite2D.flip_h = to_player.x < 0.0

	# Check if already in attack range - if so, attack directly without teleport
	if dist <= attack_range:
		_update_pass_through_bob(delta, dist)
		_try_attack_player()
		return

	var path_blocked := _is_direction_blocked(move_dir)

	# Before ring theft: if player path is blocked, switch to queen instead of teleporting.
	if not _has_hit_queen and not _forced_player_aggro and path_blocked:
		if queen != null and _is_target_alive(queen):
			_process_chase_and_attack_queen(delta)
			return
		# If queen is unavailable, try detouring to keep pressure on player.
		move_dir = _find_detour_direction(move_dir)

	# Teleport trap is only available after ring theft
	if _has_hit_queen and path_blocked:
		_update_pass_through_bob(delta, dist)
		_force_player_teleport_and_one_shot()
		return

	# Before ring theft and player is far: prioritize getting ring from queen instead of chasing distant player
	if not _has_hit_queen and not _forced_player_aggro and dist > teleport_if_player_farther_than:
		if queen != null and _is_target_alive(queen):
			_process_chase_and_attack_queen(delta)
			return

	# Chase the player
	is_attacking = false
	current_state = WALK
	$AnimatedSprite2D.play("walk")
	var chase_vel: Vector2 = move_dir * move_speed
	velocity = velocity.move_toward(chase_vel, move_speed * delta * 5.0)
	move_and_slide()

	if _has_hit_queen and dist > teleport_if_player_farther_than:
		_teleport_player_if_far()

	_update_pass_through_bob(delta, dist)


func _process_wander(delta: float) -> void:
	_reset_pass_through_bob(delta)
	if is_attacking:
		return

	match current_state:
		IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 6.0)
			move_and_slide()
			$AnimatedSprite2D.play("idle")
		WALK:
			var direction := global_position.direction_to(wander_controller.target_position)
			if global_position.distance_to(wander_controller.target_position) <= wander_target_reached_distance:
				velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 6.0)
				$AnimatedSprite2D.play("idle")
				current_state = IDLE
			else:
				$AnimatedSprite2D.play("walk")
				velocity = velocity.move_toward(direction * move_speed, move_speed * delta * 4.5)
				$AnimatedSprite2D.flip_h = velocity.x < 0.0
			move_and_slide()
		REACT:
			$AnimatedSprite2D.play("react")
		DIE:
			$AnimatedSprite2D.play("dead")
		HIT:
			$AnimatedSprite2D.play("hit")
		NEW_DIR:
			dir = [Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2.LEFT].pick_random()
			$AnimatedSprite2D.play("walk")
			current_state = WALK


func _face_target_and_attack() -> void:
	"""Turn to face player and immediately trigger attack when collision happens"""
	if player == null or not _is_target_alive(player):
		return

	# Turn to face the player
	var to_player: Vector2 = player.global_position - global_position
	if to_player.x != 0.0:
		$AnimatedSprite2D.flip_h = to_player.x < 0.0

	# Force attack by bypassing cooldown - collision takes priority
	_attack_cooldown_left = 0.0
	_attack_in_progress = false
	_try_attack_player()


func _try_attack_player() -> void:
	if _attack_in_progress or _attack_cooldown_left > 0.0 or player == null:
		return

	_attack_in_progress = true
	is_attacking = true
	current_state = ATTACK
	_attack_cooldown_left = attack_cooldown
	$AnimatedSprite2D.play("attack")

	# Calculate throw force based on ring status
	var throw_force := attack_throw_force
	if _has_hit_queen:
		throw_force *= 1.3  # 2x force after ring stolen

	if player.has_method("apply_uncontrolled_throw"):
		player.call("apply_uncontrolled_throw", global_position, throw_force, attack_throw_duration)

	await get_tree().create_timer(0.28).timeout

	# Damage based on ring status
	if player != null and _is_target_alive(player):
		if player.has_method("take_damage"):
			var heal_max := 100
			if "max_health" in player:
				heal_max = player.max_health
			var damage_amount := int(ceil(heal_max * 0.3))
			player.call("take_damage", damage_amount)

		# Slowness only applies after the ring is stolen.
		if _has_hit_queen and player.has_method("apply_skeleton_slow"):
			player.call("apply_skeleton_slow", 3.0, 1.8)

	# Retarget after hit immediately
	_retarget_timer = retarget_interval

	_attack_in_progress = false
	is_attacking = false
	if not is_dead and _current_target() != null:
		current_state = WALK


func _try_attack_queen() -> void:
	if _attack_in_progress or _attack_cooldown_left > 0.0 or queen == null:
		return

	_attack_in_progress = true
	is_attacking = true
	current_state = ATTACK
	_attack_cooldown_left = attack_cooldown
	$AnimatedSprite2D.play("attack")

	# queen hit means skeleton will now prioritize player permanently
	_has_hit_queen = true
	emit_signal("ring_stolen")
	_retarget_timer = retarget_interval  # Retarget immediately after

	await get_tree().create_timer(0.28).timeout

	# Show impact feedback even during ring-steal sequence.
	$AnimatedSprite2D.play("hit")
	await get_tree().create_timer(0.14).timeout

	# Make the queen flee
	if queen != null and queen.has_method("flee_from_skeleton"):
		queen.call("flee_from_skeleton")
	
	# Show event caption through world-style system message
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton has stolen the ring!", 3.0)
	
	# Laugh after getting the ring
	await get_tree().create_timer(0.5).timeout
	$skeletonLaughs.play()
	
	# Skeleton taunts the player
	await get_tree().create_timer(0.8).timeout
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton: Hahaha, I have the ring!", 3.0)
	
	# Keep pressure after stealing the ring; player is no longer instant-killed here.
	await get_tree().create_timer(0.6).timeout

	_attack_in_progress = false
	is_attacking = false
	if not is_dead and _current_target() != null:
		current_state = WALK


func _teleport_player_if_far() -> void:
	if player == null or not _is_target_alive(player):
		return

	var dist = global_position.distance_to(player.global_position)
	if dist <= teleport_if_player_farther_than:
		return

	global_position = player.global_position + teleport_player_offset
	
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton appeared near you!", 2.0)


func _force_player_teleport_and_one_shot() -> void:
	if player == null or not _is_target_alive(player):
		return

	global_position = player.global_position + teleport_player_offset
	# No one-shot kill: just force a close-range follow-up attack.
	_attack_cooldown_left = 0.0
	_try_attack_player()

	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton appeared near you!", 2.0)


func _is_direction_blocked(direction: Vector2) -> bool:
	if direction.length_squared() <= 0.0001:
		return false

	var from := global_position
	var to := from + direction.normalized() * chase_probe_distance
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _find_detour_direction(forward: Vector2) -> Vector2:
	if forward.length_squared() <= 0.0001:
		return Vector2.RIGHT

	var safe_forward := forward.normalized()
	if not _is_direction_blocked(safe_forward):
		return safe_forward

	var rays := maxi(3, chase_detour_scan_rays)
	if rays % 2 == 0:
		rays += 1
	var half_angle := deg_to_rad(chase_detour_scan_angle_degrees) * 0.5
	var best_dir := safe_forward
	var best_score := -INF

	for i in range(rays):
		var t := 0.0
		if rays > 1:
			t = float(i) / float(rays - 1)
		var angle := lerpf(-half_angle, half_angle, t)
		var candidate := safe_forward.rotated(angle).normalized()
		if _is_direction_blocked(candidate):
			continue
		var score := candidate.dot(safe_forward)
		if score > best_score:
			best_score = score
			best_dir = candidate

	return best_dir


func set_forced_target(target: Node, instant_kill := false, lock_target := true) -> void:
	if target.name.to_lower() == "npc":
		queen = target
		player = null
	else:
		player = target
	_target_locked = lock_target
	_instant_kill_target = instant_kill
	if player != null or queen != null:
		current_state = WALK


func _handle_ring_theft_kill() -> void:
	if player == null or not _is_target_alive(player):
		return

	# Legacy helper kept non-lethal: after ring theft, apply strong hit effects only.
	if player.has_method("take_damage"):
		var heal_max := 100
		if "max_health" in player:
			heal_max = player.max_health
		player.call("take_damage", int(ceil(heal_max * 0.3)))
	if player.has_method("apply_skeleton_slow"):
		player.call("apply_skeleton_slow", 3.0, 1.8)


func _on_detection_area_body_entered(body):
	if _target_locked:
		return
	if _is_player_target(body):
		player = body
		_instant_kill_target = false
		# Turn to face the character and trigger attack
		_face_target_and_attack()
		return


func _on_detection_area_body_exited(body):
	if _target_locked:
		return
	if _is_player_target(body):
		player = null
		_instant_kill_target = false
		is_attacking = false
		_attack_in_progress = false
		current_state = IDLE


func enemy():
	pass


func take_damage(damage: int):
	$skeletonHit.play()
	$AnimatedSprite2D.play("hit")
	await get_tree().create_timer(1).timeout
	_add_shooting_progress(1.0)
	current_health -= damage
	current_health = max(1, current_health)
	healthBar.value = current_health
	_force_target_player_after_hit()


func _force_target_player_after_hit() -> void:
	_forced_player_aggro = true
	if player == null or not _is_target_alive(player):
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
	if player == null:
		var scene := get_tree().current_scene
		if scene != null:
			var maybe_player := scene.get_node_or_null("player")
			if maybe_player != null:
				player = maybe_player
	queen = null
	_retarget_timer = retarget_interval


func _update_auto_regen(delta: float) -> void:
	var regen_threshold := float(health) * (auto_regen_below_percent / 100.0)
	if current_health >= regen_threshold:
		return

	var healed := float(current_health) + auto_regen_per_second * delta
	current_health = min(health, int(round(healed)))
	if healthBar:
		healthBar.value = current_health


func death():
	_add_shooting_progress(10.0) # Bonus for kill
	is_dead = true
	$skeletonDies.play()
	$AnimatedSprite2D.play("dead")
	
	healthBar.visible = false
	$HitBox/CollisionShape2D.disabled = true
	$DetectionArea/CollisionShape2D.disabled = true
	$DeathTimer.start()
	

func _on_hit_box_area_entered(area):
	var damage
	if area.has_method("arrow_deal_damage"):
		damage = _get_arrow_damage()
		take_damage(damage)


func _on_timer_timeout():
	$Timer.wait_time = [0.5, 1.0, 1.5].pick_random()
	wander_controller.start_wander_timer($Timer.wait_time)
	if !is_dead:
		get_state()
		$Timer.start()


func _on_death_timer_timeout():
	queue_free()


func _update_pass_through_bob(delta: float, player_distance: float) -> void:
	# Tiny bob when overlapping player space so pass-through looks intentional.
	if player_distance > 16.0:
		_reset_pass_through_bob(delta)
		return

	_pass_through_bob_phase += delta * 14.0
	var bob := absf(sin(_pass_through_bob_phase)) * 2.0
	$AnimatedSprite2D.position = Vector2(_sprite_base_position.x, _sprite_base_position.y - bob)


func _reset_pass_through_bob(delta: float) -> void:
	_pass_through_bob_phase = 0.0
	$AnimatedSprite2D.position = $AnimatedSprite2D.position.lerp(_sprite_base_position, clampf(delta * 10.0, 0.0, 1.0))
