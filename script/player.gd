extends CharacterBody2D

@export var speed := 100.0
@export var stair_speed := 60.0
@export var start_with_lamp_on := false

@export var stair_bias := 40.0    # for stair-r / stair-l
@export var stair_bias2 := 45.0   # for stair-r2 / stair-l2
@export var throw_friction := 1800.0
@export var throw_flip_interval := 0.05

var tilemap: Object
var animated_sprite: AnimatedSprite2D = null
var collision_shape: CollisionShape2D = null
var point_light: PointLight2D = null
var is_alive := true
var controls_enabled := true
var lamp_control_unlocked := false

var last_dir := Vector2.DOWN
var current_anim := ""
var _throw_active := false
var _throw_velocity := Vector2.ZERO
var _throw_time_left := 0.0
var _throw_flip_timer := 0.0
var _throw_flip_right := false


func _ready():
	print("Player _ready() called")
	
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
	
	tilemap = get_parent().get_node_or_null("TileMap")
	if tilemap == null:
		push_warning("TileMap not found in parent!")
	else:
		print("TileMap found successfully")
	
	
	print("Player initialization complete")


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		if lamp_control_unlocked and point_light:
			point_light.visible = not point_light.visible


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled


func set_lamp_control_unlocked(enabled: bool) -> void:
	lamp_control_unlocked = enabled
	if point_light and not lamp_control_unlocked:
		point_light.visible = false


func is_lamp_control_unlocked() -> bool:
	return lamp_control_unlocked


func player() -> Node:
	return self


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


func _physics_process(delta):
	if _throw_active:
		_process_uncontrolled_throw(delta)
		return

	if not controls_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		update_animation(Vector2.ZERO)
		return

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var stair_type := get_stair_type()

	var vel := input_dir * speed

	if stair_type != "":
		vel = input_dir * stair_speed

		if stair_type != "stair-m":
			vel = apply_stair_bias_velocity(vel, stair_type)

	velocity = vel
	move_and_slide()

	if input_dir != Vector2.ZERO:
		last_dir = input_dir.normalized()

	update_animation(velocity.normalized())


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


# ---------- TILE DATA ----------

func get_stair_type() -> String:
	if tilemap == null:
		return ""
	
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
	var data: TileData = tilemap.get_cell_tile_data(0, cell)

	if data == null:
		return ""

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
