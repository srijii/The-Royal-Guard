
extends CharacterBody2D

func _is_player_target(body: Node) -> bool:
	# Adjust this logic as needed for your player node
	return body != null and body.has_method("is_player") and body.is_player()

signal ring_stolen
signal requested_backup(spawn_position: Vector2)

var health = 99999
var current_health = health
@onready var healthBar = $healthBar
@onready var wander_controller = $WanderController
@export var auto_regen_below_percent := 40.0
@export var auto_regen_per_second := 18.0
@export var move_speed := 110.0
@export var attack_range := 30.0
@export var attack_cooldown := 0.9
@export var attack_throw_force := 550.0
@export var attack_throw_duration := 0.6
@export var wander_target_reached_distance := 8.0
@export var chase_probe_distance := 50.0
@export var chase_detour_scan_rays := 11
@export var chase_detour_scan_angle_degrees := 140.0

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
@export var teleport_if_player_farther_than := 200.0
@export var teleport_player_offset := Vector2(40, 0)

var _retarget_timer := 0.0

@export var queen_contact_distance := 10.0
@export var chase_give_up_time := 5.0
var _chase_frustration := 0.0
var _is_retreating := false
var _retreat_speed := 80.0

@export var rage_damage_threshold := 500
@export var rage_speed_multiplier := 1.3
@export var rage_damage_multiplier := 1.4
@export var rage_cooldown_multiplier := 0.7
var _total_damage_taken := 0
var _is_rage_active := false
var _no_target_time := 0.0
var _backup_requested := false
var _queen_ring_stolen_fast := false

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


func _has_line_of_sight_to(target: Node) -> bool:
	if target == null:
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.exclude = [self]
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	if collider == null:
		return false
	return collider == target or target.is_ancestor_of(collider)


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

	# Retreat mode: moving back to start position
	if _is_retreating:
		_process_retreat(delta)
		return

	var target := _current_target()
	if target == player:
		_chase_frustration += delta
		_no_target_time = 0.0
		if _chase_frustration >= chase_give_up_time and not _has_hit_queen and not _forced_player_aggro:
			_is_retreating = true
			_chase_frustration = 0.0
			return
		_process_chase_and_attack_player(delta)
	elif target == queen:
		_chase_frustration = 0.0
		_no_target_time = 0.0
		_process_chase_and_attack_queen(delta)
	else:
		_chase_frustration = 0.0
		_no_target_time += delta
		if _no_target_time >= 3.0 and not _backup_requested:
			_backup_requested = true
			emit_signal("requested_backup", global_position)
		_process_wander(delta)


func _current_target() -> Node:
	var player_alive := player != null and _is_target_alive(player)
	var queen_alive := queen != null and _is_target_alive(queen)

	if not player_alive and not queen_alive:
		return null

	# After stealing ring, always chase and kill player
	if _has_hit_queen:
		return player if player_alive else null

	# If player hit skeleton, force aggro on player
	if _forced_player_aggro:
		return player if player_alive else (queen if queen_alive else null)

	# Target NPC (queen) first — skeleton wants the ring.
	# Only target queen if we have line of sight to her.
	if queen_alive and _has_line_of_sight_to(queen):
		# If player gets too close, switch to player
		if player_alive and global_position.distance_to(player.global_position) <= 180.0:
			return player
		return queen

	# Queen alive but no LOS — don't chase blindly; wander or chase player if close.
	if queen_alive and player_alive and global_position.distance_to(player.global_position) <= 180.0:
		return player

	return player if player_alive else null


func _retarget_to_nearest() -> void:
	# Only clear references if both targets are actually dead (not just out of LOS)
	var next_target := _current_target()
	if next_target == null:
		var player_alive := player != null and _is_target_alive(player)
		var queen_alive := queen != null and _is_target_alive(queen)
		if not player_alive and not queen_alive:
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

	if dist <= queen_contact_distance:
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


func _process_retreat(delta: float) -> void:
	if queen != null and _is_target_alive(queen) and _has_line_of_sight_to(queen):
		_is_retreating = false
		_chase_frustration = 0.0
		return

	var to_start := start_position - global_position
	if to_start.length_squared() <= 64.0:
		_is_retreating = false
		_chase_frustration = 0.0
		current_state = IDLE
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 6.0)
		move_and_slide()
		return

	var move_dir := to_start.normalized()
	if move_dir.x != 0.0:
		$AnimatedSprite2D.flip_h = move_dir.x < 0.0
	$AnimatedSprite2D.play("walk")
	velocity = velocity.move_toward(move_dir * _retreat_speed, move_speed * delta * 5.0)
	move_and_slide()


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
		throw_force *= 1.5  # 50% stronger after ring stolen

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
			if _is_rage_active:
				damage_amount = int(ceil(damage_amount * rage_damage_multiplier))
			player.call("take_damage", damage_amount)

		# Slowness only applies after the ring is stolen.
		if _has_hit_queen and player.has_method("apply_skeleton_slow"):
			player.call("apply_skeleton_slow", 3.0, 1.8)

		# Bone splash + blood effect
		Helpers.spawn_bone_effect(player.global_position)
		Helpers.spawn_blood_effect(player.global_position)

		# Princess regeneration (slow heal over time)
		if player.has_method("apply_skeleton_regen"):
			player.call("apply_skeleton_regen", 4, 2.0)

		# Bleeding blood stains
		if player.has_method("start_bleeding"):
			player.call("start_bleeding", 6.0)

	# Retarget after hit immediately
	_retarget_timer = retarget_interval

	_chase_frustration = 0.0

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

	_has_hit_queen = true
	emit_signal("ring_stolen")
	_retarget_timer = retarget_interval

	if _instant_kill_target:
		_queen_ring_stolen_fast = true
		_attack_in_progress = false
		is_attacking = false
		if queen != null and queen.has_method("flee_from_skeleton"):
			queen.call("flee_from_skeleton")
		var scene := get_tree().get_current_scene()
		if scene and scene.has_method("_show_system_message"):
			scene.call("_show_system_message", "Backup skeleton has stolen the ring!", 3.0)
		await get_tree().create_timer(0.5).timeout
		_teleport_to_player_and_kill()
		return

	await get_tree().create_timer(0.28).timeout

	$AnimatedSprite2D.play("hit")
	await get_tree().create_timer(0.14).timeout

	if queen != null and queen.has_method("flee_from_skeleton"):
		queen.call("flee_from_skeleton")
	
	var scene = get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton has stolen the ring!", 3.0)
	
	await get_tree().create_timer(0.5).timeout
	$skeletonLaughs.play()
	
	await get_tree().create_timer(0.8).timeout
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Skeleton: Hahaha, I have the ring!", 3.0)
	
	await get_tree().create_timer(0.6).timeout

	_attack_in_progress = false
	is_attacking = false
	if not is_dead and _current_target() != null:
		current_state = WALK


func _teleport_to_player_and_kill() -> void:
	if player == null or not _is_target_alive(player):
		return
	global_position = player.global_position + teleport_player_offset
	var scene := get_tree().get_current_scene()
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Backup skeleton teleported to you!", 2.5)
	if player.has_method("take_damage"):
		player.call("take_damage", 999)
	if player.has_method("apply_skeleton_slow"):
		player.call("apply_skeleton_slow", 5.0, 3.0)
	if scene and scene.has_method("_show_system_message"):
		scene.call("_show_system_message", "Backup skeleton killed you!", 3.0)


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
	Helpers.spawn_blood_effect(global_position)
	Helpers.spawn_blood_stain(global_position)
	$skeletonHit.play()
	$AnimatedSprite2D.play("hit")
	_force_target_player_after_hit()
	_total_damage_taken += damage
	if not _is_rage_active and _total_damage_taken >= rage_damage_threshold:
		_activate_rage_mode()


func _force_target_player_after_hit() -> void:
	_forced_player_aggro = true
	_is_retreating = false
	_chase_frustration = 0.0
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


func _activate_rage_mode() -> void:
	_is_rage_active = true
	if $AnimatedSprite2D:
		$AnimatedSprite2D.modulate = Color(1.0, 0.2, 0.2, 1.0)
	move_speed *= rage_speed_multiplier
	attack_throw_force *= rage_damage_multiplier
	attack_cooldown *= rage_cooldown_multiplier
	auto_regen_below_percent = 60.0
	auto_regen_per_second *= 2.5


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
