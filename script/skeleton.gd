extends CharacterBody2D

var health = 300
var current_health = health
@onready var healthBar = $healthBar
@onready var wander_controller = $WanderController
@export var move_speed := 95.0
@export var attack_range := 38.0
@export var attack_cooldown := 1.0
@export var attack_throw_force := 700.0
@export var attack_throw_duration := 0.95
@export var wander_target_reached_distance := 10.0

var dir = Vector2.RIGHT
var start_position: Vector2
enum { IDLE, REACT, WALK, DIE, ATTACK, HIT, NEW_DIR }
var current_state = IDLE

var is_roaming = true
var is_attacking = false
var is_dead = false

var player = null
var _attack_cooldown_left := 0.0
var _attack_in_progress := false


func _get_player_stats() -> Node:
	return get_node_or_null("/root/PlayerStats")


func _choose(array: Array):
	var helpers := get_node_or_null("/root/Helpers")
	if helpers and helpers.has_method("choose"):
		return helpers.call("choose", array)
	array.shuffle()
	return array.front()


func _is_player_target(body: Node) -> bool:
	if body == null:
		return false
	if body.has_method("player"):
		return true
	return body.name.to_lower() == "player"


func _has_property(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if String(p.name) == prop_name:
			return true
	return false


func _is_target_alive(target: Node) -> bool:
	if target == null:
		return false
	if target.has_method("is_alive"):
		return bool(target.call("is_alive"))
	if _has_property(target, "is_alive"):
		return bool(target.get("is_alive"))
	return true


func _add_shooting_progress(amount: float) -> void:
	var stats := _get_player_stats()
	if stats and stats.has_method("shooting_level"):
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
	start_position = position
	healthBar.value = current_health
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

	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)

	if player != null and _is_target_alive(player):
		_process_chase_and_attack(delta)
	else:
		_process_wander(delta)


func _process_chase_and_attack(delta: float) -> void:
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist <= 0.001:
		to_player = Vector2.RIGHT

	if to_player.x != 0.0:
		$AnimatedSprite2D.flip_h = to_player.x < 0.0

	if dist > attack_range:
		is_attacking = false
		current_state = WALK
		$AnimatedSprite2D.play("walk")
		var chase_vel: Vector2 = to_player.normalized() * move_speed
		velocity = velocity.move_toward(chase_vel, move_speed * delta * 5.0)
		move_and_slide()
		return

	# In range: stop and attack when off cooldown.
	velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 7.0)
	move_and_slide()
	_try_attack_player()


func _process_wander(delta: float) -> void:
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
			dir = _choose([Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2.LEFT])
			$AnimatedSprite2D.play("walk")
			current_state = WALK


func _try_attack_player() -> void:
	if _attack_in_progress or _attack_cooldown_left > 0.0 or player == null:
		return

	_attack_in_progress = true
	is_attacking = true
	current_state = ATTACK
	_attack_cooldown_left = attack_cooldown
	$AnimatedSprite2D.play("attack")

	if player.has_method("apply_uncontrolled_throw"):
		player.call("apply_uncontrolled_throw", global_position, attack_throw_force, attack_throw_duration)

	await get_tree().create_timer(0.28).timeout

	_attack_in_progress = false
	is_attacking = false
	if not is_dead and player != null and _is_target_alive(player):
		current_state = WALK


func _on_detection_area_body_entered(body):
	if _is_player_target(body):
		player = body
		current_state = REACT
		$AnimatedSprite2D.play("react")
		$skeletonLaughs.play()
		await get_tree().create_timer(1).timeout
		current_state = WALK


func _on_detection_area_body_exited(body):
	if _is_player_target(body):
		player = null
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
	healthBar.value = current_health
	if current_health <= 0 and !is_dead:
		death()


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
	$Timer.wait_time = _choose([0.5, 1.0, 1.5])
	wander_controller.start_wander_timer($Timer.wait_time)
	if !is_dead:
		get_state()
		$Timer.start()


func _on_death_timer_timeout():
	queue_free()
