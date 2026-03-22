extends Node2D

@export var spawn_npc_on_start := true
@export var npc_spawn_offset := Vector2(96, 0)
@export var npc_scene: PackedScene = preload("res://scene/npc.tscn")
@export var skeleton_scene: PackedScene = preload("res://scene/skeleton.tscn")
@export var torch_scene: PackedScene = preload("res://scene/torch.tscn")
@export var palace_map_scene: PackedScene = preload("res://scene/palace_map.tscn")
@export var clock_scene: PackedScene = preload("res://scene/clock.tscn")
@export var skeleton_night_spawn_offset := Vector2(120, 24)
@export var princess_wander_area := Rect2(Vector2(-600, -360), Vector2(1200, 900))
@export var use_polygon_wander_zone := true
@export var wander_zone_polygon_path: NodePath = NodePath("PrincessWanderZone/CollisionPolygon2D")
@export var princess_checkpoints: Array[Vector2] = [
	Vector2(-260, -150),
	Vector2(120, -180),
	Vector2(460, 40),
	Vector2(140, 280),
	Vector2(-220, 220)
]

const SAVE_PATH := "user://savegame.json"

var _npc_instance: Node2D = null
var _loaded_from_save := false
var _pause_layer: CanvasLayer = null
var _pause_panel: PanelContainer = null
var _night_skeleton_spawned := false
var _night_skeleton_spawn_pending := false
var _player_instance: Node2D = null

var _intro_exploration_active := false
var _intro_return_started := false
var _has_torch := false
var _map_read := false

var _intro_hud_layer: CanvasLayer = null
var _objective_label: Label = null
var _prompt_label: Label = null
var _system_message_label: Label = null
var _system_message_time_left := 0.0
var _coordinate_label: Label = null
var _coordinate_display_time_left := 0.0
var _torch_pickup_node: Node2D = null
var _torch_pickup_anim: AnimatedSprite2D = null
var _torch_follower_node: Node2D = null
var _torch_follower_anim: AnimatedSprite2D = null
var _torch_follow_phase := 0.0

var _map_pos := Vector2(157, -158)
var _clock_pos := Vector2(300, -200)
var _torch_pos := Vector2(495, -5)
var _interaction_radius := 72.0

var _map_node: Node2D = null
var _clock_node: Node2D = null
var _current_interactable: Node = null

func _ready() -> void:
	# Keep this node processing while paused so Esc can resume from pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_pause_menu()
	_create_intro_hud()
	_create_torch_pickup_node()
	_create_torch_follower_node()

	if not spawn_npc_on_start:
		return

	_player_instance = get_node_or_null("player") as Node2D
	if _player_instance == null:
		push_warning("Player node not found. NPC was not spawned.")
		return
	if _player_instance.has_method("set_lamp_control_unlocked"):
		_player_instance.call("set_lamp_control_unlocked", false)

	if npc_scene == null:
		push_warning("NPC scene is not assigned. NPC was not spawned.")
		return

	_npc_instance = npc_scene.instantiate() as Node2D
	if _npc_instance == null:
		push_warning("Failed to instantiate NPC scene.")
		return

	_npc_instance.name = "npc"
	_npc_instance.position = _player_instance.position + npc_spawn_offset
	add_child(_npc_instance)
	if _npc_instance.has_signal("night_started"):
		_npc_instance.connect("night_started", Callable(self, "_on_npc_night_started"))
	if _npc_instance.has_signal("exploration_started"):
		_npc_instance.connect("exploration_started", Callable(self, "_on_intro_exploration_started"))

	# Configure princess wandering region and pause/look checkpoints.
	var polygon_points := PackedVector2Array()
	if use_polygon_wander_zone:
		polygon_points = _get_wander_polygon_world_points()
	var flower_points := _get_flower_world_points()

	if _npc_instance.has_method("configure_princess_behavior"):
		_npc_instance.call("configure_princess_behavior", princess_wander_area, princess_checkpoints, polygon_points, flower_points)

	# Create interactable nodes
	_create_interactable_nodes()

	_load_game_if_exists(_player_instance)
	_apply_torch_visual_state()


func _process(delta: float) -> void:
	_update_system_message(delta)
	_update_intro_interaction_prompt()
	_update_intro_return_trigger()
	_update_torch_follower(delta)
	_update_coordinate_display(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if _intro_exploration_active:
				_try_intro_interaction()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			_show_coordinates()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game_state()
		get_tree().quit()


func _load_game_if_exists(player_node: Node2D) -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parsed
	if data.get("scene", "") != "res://scene/world.tscn":
		return

	if data.has("player_position"):
		player_node.global_position = Vector2(data["player_position"]["x"], data["player_position"]["y"])

	if data.has("player_light_on") and player_node.has_node("PointLight2D"):
		var light := player_node.get_node("PointLight2D") as PointLight2D
		if light:
			light.visible = bool(data["player_light_on"])

	var lamp_unlocked := bool(data.get("player_lamp_unlocked", bool(data.get("npc_night_started", false))))
	if player_node.has_method("set_lamp_control_unlocked"):
		player_node.call("set_lamp_control_unlocked", lamp_unlocked)

	if _npc_instance:
		if _npc_instance.has_method("apply_saved_state"):
			_npc_instance.call("apply_saved_state", data)
		else:
			if data.has("npc_position"):
				_npc_instance.global_position = Vector2(data["npc_position"]["x"], data["npc_position"]["y"])

	var inferred_intro_active := bool(data.get("npc_story_completed", true)) and not bool(data.get("intro_return_started", false)) and not bool(data.get("npc_night_started", false))
	_intro_exploration_active = bool(data.get("intro_exploration_active", inferred_intro_active))
	_intro_return_started = bool(data.get("intro_return_started", false))
	_has_torch = bool(data.get("has_torch", bool(data.get("has_royal_sword", false))))
	_map_read = bool(data.get("map_read", false))

	if _intro_exploration_active:
		if _has_torch:
			_set_objective_text("Quest: Return to the princess before midnight")
		else:
			_set_objective_text("Quest: Find the Torch")
	else:
		_set_objective_text("")
	_set_prompt_text("")

	if has_node("CanvasModulate") and data.has("night_color"):
		var cm := get_node("CanvasModulate") as CanvasModulate
		if cm:
			var c = data["night_color"]
			cm.color = Color(float(c["r"]), float(c["g"]), float(c["b"]), float(c["a"]))
			cm.visible = bool(data.get("night_visible", false))

	_restore_night_skeleton_from_save(data)
	_apply_torch_visual_state()

	_loaded_from_save = true
	print("Loaded saved game state.")


func _save_game_state() -> void:
	var player_node := get_node_or_null("player") as Node2D
	if player_node == null:
		return

	var save_data: Dictionary = {
		"scene": "res://scene/world.tscn",
		"player_position": {
			"x": player_node.global_position.x,
			"y": player_node.global_position.y
		},
		"saved_at_unix": Time.get_unix_time_from_system()
	}

	if player_node.has_node("PointLight2D"):
		var light := player_node.get_node("PointLight2D") as PointLight2D
		if light:
			save_data["player_light_on"] = light.visible
	if player_node.has_method("is_lamp_control_unlocked"):
		save_data["player_lamp_unlocked"] = bool(player_node.call("is_lamp_control_unlocked"))

	if _npc_instance:
		save_data["npc_position"] = {
			"x": _npc_instance.global_position.x,
			"y": _npc_instance.global_position.y
		}
		if _npc_instance.has_method("get_save_state"):
			var npc_state: Dictionary = _npc_instance.call("get_save_state")
			for key in npc_state.keys():
				save_data[key] = npc_state[key]

	save_data["intro_exploration_active"] = _intro_exploration_active
	save_data["intro_return_started"] = _intro_return_started
	save_data["has_torch"] = _has_torch
	save_data["has_royal_sword"] = _has_torch
	save_data["map_read"] = _map_read

	var night_skeleton := get_node_or_null("NightSkeleton") as Node2D
	save_data["night_skeleton_present"] = night_skeleton != null
	if night_skeleton:
		save_data["night_skeleton_position"] = {
			"x": night_skeleton.global_position.x,
			"y": night_skeleton.global_position.y
		}

	if has_node("CanvasModulate"):
		var cm := get_node("CanvasModulate") as CanvasModulate
		if cm:
			save_data["night_visible"] = cm.visible
			save_data["night_color"] = {
				"r": cm.color.r,
				"g": cm.color.g,
				"b": cm.color.b,
				"a": cm.color.a
			}

	var json_text := JSON.stringify(save_data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_text)
		print("Saved game state.")


func _restore_night_skeleton_from_save(data: Dictionary) -> void:
	var existing := get_node_or_null("NightSkeleton") as Node2D
	if existing:
		_night_skeleton_spawned = true
		_night_skeleton_spawn_pending = false
		return

	var npc_night_started := bool(data.get("npc_night_started", false))
	if not npc_night_started:
		_night_skeleton_spawned = false
		_night_skeleton_spawn_pending = false
		return

	var should_have_skeleton := bool(data.get("night_skeleton_present", true))
	if not should_have_skeleton:
		_night_skeleton_spawned = false
		_night_skeleton_spawn_pending = false
		return

	if skeleton_scene == null:
		return

	var skeleton := skeleton_scene.instantiate() as Node2D
	if skeleton == null:
		return

	skeleton.name = "NightSkeleton"
	if data.has("night_skeleton_position"):
		var p = data["night_skeleton_position"]
		skeleton.global_position = Vector2(float(p["x"]), float(p["y"]))
	else:
		var spawn_origin := Vector2.ZERO
		if _npc_instance:
			spawn_origin = _npc_instance.global_position
		skeleton.global_position = spawn_origin + skeleton_night_spawn_offset

	add_child(skeleton)
	_night_skeleton_spawned = true
	_night_skeleton_spawn_pending = false


func _create_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 50
	_pause_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_pause_layer)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(overlay)

	_pause_panel = PanelContainer.new()
	_pause_panel.custom_minimum_size = Vector2(300, 160)
	_pause_panel.anchor_left = 0.5
	_pause_panel.anchor_top = 0.5
	_pause_panel.anchor_right = 0.5
	_pause_panel.anchor_bottom = 0.5
	_pause_panel.position = Vector2(-150, -80)
	overlay.add_child(_pause_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	panel_style.border_color = Color(0.9, 0.8, 0.35, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1

	var panel_theme := Theme.new()
	panel_theme.set_stylebox("panel", "PanelContainer", panel_style)
	_pause_panel.theme = panel_theme

	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(root)

	var title := Label.new()
	title.text = "Game Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(0, 36)
	continue_button.pressed.connect(_resume_game)
	root.add_child(continue_button)

	var main_menu_button := Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.custom_minimum_size = Vector2(0, 36)
	main_menu_button.pressed.connect(_go_to_main_menu)
	root.add_child(main_menu_button)

	_pause_layer.visible = false


func _pause_game() -> void:
	if _pause_layer:
		_pause_layer.visible = true
	get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	if _pause_layer:
		_pause_layer.visible = false


func _go_to_main_menu() -> void:
	_save_game_state()
	_resume_game()
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


func _on_npc_night_started(_queen_position: Vector2) -> void:
	if _night_skeleton_spawned or _night_skeleton_spawn_pending:
		return
	_night_skeleton_spawn_pending = true
	_set_prompt_text("")
	_set_objective_text("Defend the princess from skeleton thieves")
	_show_system_message("Night event started. Skeletons incoming...")
	await get_tree().create_timer(3.0).timeout
	_spawn_skeleton_near_queen()


func _on_intro_exploration_started() -> void:
	_intro_exploration_active = true
	_intro_return_started = false
	_has_torch = false
	_set_objective_text("Quest: Find the Torch")
	_show_system_message("Explore: read map, check clock, and find the Torch.")


func _create_intro_hud() -> void:
	_intro_hud_layer = CanvasLayer.new()
	_intro_hud_layer.layer = 60
	add_child(_intro_hud_layer)

	_objective_label = Label.new()
	_objective_label.anchor_left = 0.0
	_objective_label.anchor_top = 0.0
	_objective_label.anchor_right = 0.0
	_objective_label.anchor_bottom = 0.0
	_objective_label.position = Vector2(16, 16)
	_objective_label.size = Vector2(760, 40)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_hud_layer.add_child(_objective_label)

	_prompt_label = Label.new()
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.position = Vector2(-260, -62)
	_prompt_label.size = Vector2(520, 28)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_hud_layer.add_child(_prompt_label)

	_system_message_label = Label.new()
	_system_message_label.anchor_left = 0.5
	_system_message_label.anchor_top = 0.0
	_system_message_label.anchor_right = 0.5
	_system_message_label.anchor_bottom = 0.0
	_system_message_label.position = Vector2(-340, 56)
	_system_message_label.size = Vector2(680, 46)
	_system_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_system_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_system_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_system_message_label.visible = false
	_intro_hud_layer.add_child(_system_message_label)

	_coordinate_label = Label.new()
	_coordinate_label.anchor_left = 1.0
	_coordinate_label.anchor_top = 0.0
	_coordinate_label.anchor_right = 1.0
	_coordinate_label.anchor_bottom = 0.0
	_coordinate_label.position = Vector2(-16, 16)
	_coordinate_label.size = Vector2(300, 40)
	_coordinate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coordinate_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_coordinate_label.add_theme_font_size_override("font_size", 14)
	_coordinate_label.visible = false
	_intro_hud_layer.add_child(_coordinate_label)

	_set_objective_text("")
	_set_prompt_text("")


func _set_objective_text(text: String) -> void:
	if _objective_label:
		_objective_label.text = text


func _set_prompt_text(text: String) -> void:
	if _prompt_label:
		_prompt_label.text = text


func _show_system_message(text: String, duration := 3.0) -> void:
	if _system_message_label == null:
		return
	_system_message_label.text = text
	_system_message_label.visible = true
	_system_message_time_left = duration


func _update_system_message(delta: float) -> void:
	if _system_message_label == null:
		return
	if _system_message_time_left <= 0.0:
		return
	_system_message_time_left -= delta
	if _system_message_time_left <= 0.0:
		_system_message_label.visible = false


func _show_coordinates() -> void:
	if _player_instance == null or _coordinate_label == null:
		return
	_coordinate_display_time_left = 3.0
	_coordinate_label.visible = true
	_update_coordinate_display(0.0)


func _update_coordinate_display(delta: float) -> void:
	if _coordinate_label == null:
		return
	
	_coordinate_display_time_left -= delta
	
	if _coordinate_display_time_left <= 0.0:
		_coordinate_label.visible = false
		return
	
	if _player_instance:
		var x = int(_player_instance.global_position.x)
		var y = int(_player_instance.global_position.y)
		_coordinate_label.text = "X: %d\nY: %d" % [x, y]


func _update_intro_interaction_prompt() -> void:
	if not _intro_exploration_active or _player_instance == null:
		return

	var prompt := ""
	_current_interactable = null
	
	# Check interactable nodes first
	if not _map_read and _map_node and _map_node.is_player_in_range():
		prompt = "Press E: Read palace map"
		_current_interactable = _map_node
	elif _clock_node and _clock_node.is_player_in_range():
		prompt = "Press E: Check clock"
		_current_interactable = _clock_node
	elif not _has_torch and _is_player_near(_torch_pos):
		prompt = "Press E: Pick up Torch"

	_set_prompt_text(prompt)


func _update_intro_return_trigger() -> void:
	if not _intro_exploration_active:
		return
	if not _has_torch:
		return
	if _intro_return_started:
		return
	if _player_instance == null or _npc_instance == null:
		return

	if _player_instance.global_position.distance_to(_npc_instance.global_position) <= 90.0:
		_intro_return_started = true
		_intro_exploration_active = false
		_set_prompt_text("")
		_show_system_message("You returned with the Torch.")
		if _npc_instance.has_method("start_return_with_torch_sequence"):
			_npc_instance.call("start_return_with_torch_sequence")
		elif _npc_instance.has_method("start_return_with_sword_sequence"):
			_npc_instance.call("start_return_with_sword_sequence")


func _try_intro_interaction() -> void:
	if _player_instance == null:
		return

	# Map interaction
	if _current_interactable and not _map_read and _map_node == _current_interactable:
		if await _map_node.try_interact():
			_map_read = true
			_show_system_message("Map: Storage room east, garden center, exits south.", 4.0)
		return

	# Clock interaction
	if _current_interactable and _clock_node == _current_interactable:
		if await _clock_node.try_interact():
			_show_system_message("Clock shows the time until midnight.", 3.0)
		return

	# Torch pickup
	if not _has_torch and _is_player_near(_torch_pos):
		_has_torch = true
		_set_objective_text("Quest: Return to the princess before midnight")
		_show_system_message("Torch acquired. Return to the princess.")
		_apply_torch_visual_state()


func _on_map_interacted(_name: String) -> void:
	pass  # Handled by _try_intro_interaction


func _create_torch_pickup_node() -> void:
	if _torch_pickup_node != null:
		return

	_torch_pickup_node = Node2D.new()
	if torch_scene:
		_torch_pickup_node = torch_scene.instantiate() as Node2D
	else:
		_torch_pickup_node = Node2D.new()

	if _torch_pickup_node == null:
		return

	_torch_pickup_node.name = "TorchPickup"
	_torch_pickup_node.global_position = _torch_pos
	add_child(_torch_pickup_node)

	_torch_pickup_anim = _torch_pickup_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _torch_pickup_anim:
		_torch_pickup_anim.play("idle")


func _create_torch_follower_node() -> void:
	if _torch_follower_node != null:
		return

	if torch_scene:
		_torch_follower_node = torch_scene.instantiate() as Node2D
	else:
		_torch_follower_node = Node2D.new()

	if _torch_follower_node == null:
		return

	_torch_follower_node.name = "TorchFollower"
	_torch_follower_node.visible = false
	add_child(_torch_follower_node)

	_torch_follower_anim = _torch_follower_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _torch_follower_anim:
		_torch_follower_anim.play("idle")


func _apply_torch_visual_state() -> void:
	if _torch_pickup_node:
		_torch_pickup_node.visible = not _has_torch

	if _torch_follower_node:
		var lamp_unlocked := false
		var torch_called := false
		if _player_instance and _player_instance.has_method("is_lamp_control_unlocked"):
			lamp_unlocked = bool(_player_instance.call("is_lamp_control_unlocked"))
		if _player_instance and _player_instance.has_node("PointLight2D"):
			var light := _player_instance.get_node("PointLight2D") as PointLight2D
			if light:
				torch_called = light.visible
		_torch_follower_node.visible = _has_torch and lamp_unlocked and torch_called


func _create_interactable_nodes() -> void:
	# Map
	if palace_map_scene:
		_map_node = palace_map_scene.instantiate() as Node2D
		if _map_node:
			_map_node.name = "Map"
			_map_node.global_position = _map_pos
			add_child(_map_node)
			if _map_node.has_signal("interaction_completed"):
				_map_node.connect("interaction_completed", Callable(self, "_on_map_interacted"))
	
	# Clock
	if clock_scene:
		_clock_node = clock_scene.instantiate() as Node2D
		if _clock_node:
			_clock_node.name = "Clock"
			_clock_node.global_position = _clock_pos
			add_child(_clock_node)


func _update_torch_follower(delta: float) -> void:
	if _torch_follower_node == null or _player_instance == null:
		return

	_apply_torch_visual_state()
	if not _torch_follower_node.visible:
		return

	_torch_follow_phase += delta * 4.6
	var bob := sin(_torch_follow_phase) * 6.0
	var target := _player_instance.global_position + Vector2(18.0, -34.0 + bob)
	_torch_follower_node.global_position = _torch_follower_node.global_position.lerp(target, clampf(delta * 8.0, 0.0, 1.0))


func _is_player_near(point: Vector2) -> bool:
	if _player_instance == null:
		return false
	return _player_instance.global_position.distance_to(point) <= _interaction_radius


func _spawn_skeleton_near_queen() -> void:
	if _night_skeleton_spawned or skeleton_scene == null:
		_night_skeleton_spawn_pending = false
		return

	var spawn_origin := Vector2.ZERO
	if _npc_instance:
		spawn_origin = _npc_instance.global_position

	var skeleton := skeleton_scene.instantiate() as Node2D
	if skeleton == null:
		_night_skeleton_spawn_pending = false
		return

	skeleton.name = "NightSkeleton"
	skeleton.global_position = spawn_origin + skeleton_night_spawn_offset
	add_child(skeleton)
	_night_skeleton_spawned = true
	_night_skeleton_spawn_pending = false


func _get_wander_polygon_world_points() -> PackedVector2Array:
	var poly_node := get_node_or_null(wander_zone_polygon_path) as CollisionPolygon2D
	if poly_node == null:
		return PackedVector2Array()

	if poly_node.polygon.size() < 3:
		return PackedVector2Array()

	var world_points := PackedVector2Array()
	for p in poly_node.polygon:
		world_points.append(poly_node.to_global(p))

	return world_points


func _get_flower_world_points() -> Array[Vector2]:
	var points: Array[Vector2] = []

	# Preferred: explicit group-based flower spots.
	for node in get_tree().get_nodes_in_group("princess_flower"):
		var n2d := node as Node2D
		if n2d:
			points.append(n2d.global_position)
			print("DEBUG WORLD: Found flower from group 'princess_flower' at %s" % [n2d.global_position])

	# Fallback: nodes named FlowerSpot, FlowerSpot2...FlowerSpot13, etc.
	_collect_named_flower_points(self, points)
	print("DEBUG WORLD: Collected %d total flowers (group + named)" % [points.size()])
	return points


func _collect_named_flower_points(node: Node, points: Array[Vector2]) -> void:
	for child in node.get_children():
		var n2d := child as Node2D
		if n2d and n2d.name.begins_with("FlowerSpot"):
			if not points.has(n2d.global_position):
				points.append(n2d.global_position)
				print("DEBUG WORLD: Found named flower '%s' at %s" % [n2d.name, n2d.global_position])
		_collect_named_flower_points(child, points)
