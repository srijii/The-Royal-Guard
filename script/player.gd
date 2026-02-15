extends CharacterBody2D

@export var speed := 100.0
@export var stair_speed := 60.0

@export var stair_bias := 40.0    # for stair-r / stair-l
@export var stair_bias2 := 45.0   # for stair-r2 / stair-l2

@onready var tilemap := get_parent().get_node("TileMap")

var last_dir := Vector2.DOWN
var current_anim := ""


func _physics_process(delta):
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


# ---------- TILE DATA ----------

func get_stair_type() -> String:
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
		$AnimatedSprite2D.play(anim)


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
