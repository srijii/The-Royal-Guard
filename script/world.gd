extends Node2D


signal _death_respawn_pressed

const PAUSE_KEY_ACTIONS := {
	"ui_up": "Move Up",
	"ui_down": "Move Down",
	"ui_left": "Move Left",
	"ui_right": "Move Right",
	"hold_map_zoom": "Show Map (Zoom Out)",
	"attack": "Attack",
	"sprint": "Sprint",
	"use_health_potion": "Use Regeneration",
	"use_strength_potion": "Use Strength Potion",
	"use_energy_drink": "Use Energy Drink",
}

@export var spawn_npc_on_start := true
@export var npc_spawn_offset := Vector2(0, -100)
@export var npc_scene: PackedScene = preload("res://scene/npc.tscn")
@export var skeleton_scene: PackedScene = preload("res://scene/skeleton.tscn")
@export var backup_spawn_radius := 60.0
@export var torch_scene: PackedScene = preload("res://scene/torch.tscn")
@export var palace_map_scene: PackedScene = preload("res://scene/palace_map.tscn")
@export var skeleton_night_spawn_position := Vector2(239, 127)
@export var princess_wander_area := Rect2(Vector2(-600, -360), Vector2(1200, 900))
@export var queen_escape_trigger_distance := 56.0
@export var queen_escape_teleport_distance := 220.0
@export var queen_escape_count_min := 2
@export var queen_escape_count_max := 3
@export var player_skeleton_engage_distance := 84.0
@export var death_black_fade_seconds := 1.1
@export var death_loading_seconds := 5.0
@export var post_death_scene := "res://scene/outerworld.tscn"
@export var queen_wait_start_distance := 86.0
@export var queen_wait_to_night_seconds := 10.0
@export var use_polygon_wander_zone := true
@export var wander_zone_polygon_path: NodePath = NodePath("PrincessWanderZone/CollisionPolygon2D")
@export var queen_trick_teleport_points: Array[Vector2] = [
	Vector2(-183, 257),
	Vector2(173, 257),
	Vector2(24, 358)
]
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
var _pause_help_panel: PanelContainer = null
var _pause_help_label: RichTextLabel = null
var _pause_help_opened_from_gameplay := false
var _pause_settings_dialog: AcceptDialog = null
var _pause_keybind_buttons: Dictionary = {}
var _frozen_character_modes: Dictionary = {}
var _manual_pause_freeze_active := false
var _night_skeleton_spawned := false
var _night_skeleton_spawn_pending := false
var _night_skeleton_instance: Node2D = null
var _night_event_running := false
var _night_player_quest_active := false
var _night_player_quest_engaged := false
var _night_help_line_spoken := false
var _player_instance: Node2D = null
var _queen_trick_teleport_index := 0
var _awaiting_player_near_queen_for_night := false
var _queen_night_countdown_running := false
var _queen_night_countdown_left := 0.0

var _intro_exploration_active := false
var _intro_return_started := false
var _has_torch := false
var _map_read := false
var _ring_stolen := false

var _intro_hud_layer: CanvasLayer = null
var _objective_label: Label = null
var _prompt_label: Label = null
var _item_prompt_label: Label = null

var _system_message_bg: ColorRect = null
var _system_message_label: Label = null
var _system_message_time_left := 0.0
var _system_message_typing := false
var _system_message_skip_requested := false
var _system_message_queue: Array = []  # Queue for messages
var _system_message_processing := false  # Flag to prevent concurrent processing
var _darkness_hint_label: Label = null
var _ring_warning_panel: PanelContainer = null
var _ring_warning_label: Label = null
var _ring_warning_time_left := 0.0
var _coordinate_label: Label = null
var _player_hearts: Array[Label] = []
var _potion_count_labels: Dictionary = {}
var _energy_bar: ProgressBar = null
var _strength_bar: ProgressBar = null
var _torch_pickup_node: Node2D = null
var _torch_pickup_anim: AnimatedSprite2D = null
var _torch_follower_node: Node2D = null
var _torch_follower_anim: AnimatedSprite2D = null
var _torch_follow_phase := 0.0

var _item_spawn_positions := [
	Vector2(-1019, -504),
	Vector2(606, -443),
	Vector2(530, 530),
	Vector2(268, 63),
	Vector2(-248, 424),
	Vector2(-259, -254),
	Vector2(649, 656),
	Vector2(1016, -242),
	Vector2(-566, 365),
	Vector2(-1033, 589),
	Vector2(-600, -240),
	Vector2(-564, -476),
	Vector2(-73,662),
	Vector2(-16,-443),
	Vector2(48, -273),
	Vector2(845,-585),
]
var _map_pos := Vector2.ZERO
var _torch_pos := Vector2.ZERO
var _interaction_radius := 72.0

var _map_node: Node2D = null
var _current_interactable: Node = null

var _death_overlay_layer: CanvasLayer = null
var _death_overlay_fade: ColorRect = null
var _death_overlay_logo: Label = null
var _death_overlay_loading: ProgressBar = null
var _death_overlay_respawn_button: Button = null
var _death_overlay_you_died_label: Label = null
var _death_sequence_started := false

# Track time since night quest started for teleport logic
var _night_quest_wait_time := 0.0


func _on_skeleton_ring_stolen() -> void:
	_ring_stolen = true
	_show_ring_stolen_warning()

func _ready() -> void:
	# Keep this node processing while paused so Esc can resume from pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Randomize torch and map spawn positions
	_item_spawn_positions.shuffle()
	_torch_pos = _item_spawn_positions[0]
	_map_pos = _item_spawn_positions[1]
	
	_create_pause_menu()
	_create_intro_hud()
	_create_death_overlay()
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
	if _player_instance.has_signal("died") and not _player_instance.is_connected("died", Callable(self, "_on_player_died")):
		_player_instance.connect("died", Callable(self, "_on_player_died"))

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
	if _npc_instance.has_signal("return_briefing_ready"):
		_npc_instance.connect("return_briefing_ready", Callable(self, "_on_npc_return_briefing_ready"))

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
	_update_darkness_hint(delta)
	_update_ring_warning(delta)
	_update_intro_interaction_prompt()
	_update_intro_return_trigger()
	_update_torch_follower(delta)
	_update_coordinate_display(delta)
	_update_queen_wait_night_countdown(delta)
	_update_night_player_quest_trigger()

	# Update player hearts if available
	if _player_instance != null and not _player_hearts.is_empty():
		if "current_health" in _player_instance and "max_health" in _player_instance:
			var hp_percent := float(_player_instance.current_health) / maxf(1.0, float(_player_instance.max_health)) * 100.0
			_set_player_hearts(hp_percent)

	_update_potion_inventory()
	_update_resource_bars()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_handle_pause_help_hotkey()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			if _intro_exploration_active:
				_try_intro_interaction()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F8:
			_debug_skip_torch_and_map_step()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			_show_coordinates()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if _system_message_typing:
				_system_message_skip_requested = true
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
		if _has_torch and _map_read:
			_set_objective_text("Quest: Return to the princess before midnight")
		elif _has_torch:
			_set_objective_text("Quest: Read the map")
		else:
			_set_objective_text("Quest: Find the Torch and map")
	else:
		var npc_story_started := bool(data.get("npc_story_sequence_started", false))
		var npc_story_done := bool(data.get("npc_story_completed", false))
		if npc_story_started and not npc_story_done:
			_set_objective_text("Quest: Find the Torch and map")
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
	_apply_map_visual_state()

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
		_night_skeleton_instance = existing
		_connect_skeleton_ring_signal(existing)
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
		skeleton.global_position = skeleton_night_spawn_position

	add_child(skeleton)
	_connect_skeleton_ring_signal(skeleton)
	_night_skeleton_instance = skeleton
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
	_pause_panel.custom_minimum_size = Vector2(360, 250)
	_pause_panel.anchor_left = 0.5
	_pause_panel.anchor_top = 0.5
	_pause_panel.anchor_right = 0.5
	_pause_panel.anchor_bottom = 0.5
	_pause_panel.position = Vector2(-180, -125)
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

	var help_button := Button.new()
	help_button.text = "Help"
	help_button.custom_minimum_size = Vector2(0, 36)
	help_button.pressed.connect(_show_pause_help)
	root.add_child(help_button)

	var main_menu_button := Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.custom_minimum_size = Vector2(0, 36)
	main_menu_button.pressed.connect(_go_to_main_menu)
	root.add_child(main_menu_button)

	var hint := Label.new()
	hint.text = "Press H to open keybind help"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

	_build_pause_settings_dialog()
	_build_pause_help_panel()

	_pause_layer.visible = false


func _pause_game() -> void:
	_set_characters_frozen(true)
	_pause_help_opened_from_gameplay = false
	if _pause_help_panel:
		_pause_help_panel.visible = false
	if _pause_layer:
		_pause_layer.visible = true
	get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	_set_characters_frozen(false)
	if _pause_layer:
		_pause_layer.visible = false


func _set_characters_frozen(frozen: bool) -> void:
	var current := get_tree().current_scene
	if current == null:
		return

	if frozen:
		if _manual_pause_freeze_active:
			return
		_frozen_character_modes.clear()
		var bodies := current.find_children("*", "CharacterBody2D", true, false)
		for node in bodies:
			if not (node is CharacterBody2D):
				continue
			var body := node as CharacterBody2D
			_frozen_character_modes[body] = body.process_mode
			body.velocity = Vector2.ZERO
			if body.has_method("set_controls_enabled"):
				body.call("set_controls_enabled", false)
			body.process_mode = Node.PROCESS_MODE_DISABLED
		_manual_pause_freeze_active = true
		return

	if not _manual_pause_freeze_active:
		return

	for body in _frozen_character_modes.keys():
		if not is_instance_valid(body):
			continue
		body.process_mode = int(_frozen_character_modes[body])
		if body.has_method("set_controls_enabled") and body.is_in_group("player"):
			body.call("set_controls_enabled", true)

	_frozen_character_modes.clear()
	_manual_pause_freeze_active = false


func _go_to_main_menu() -> void:
	_save_game_state()
	_resume_game()
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


func _open_pause_settings() -> void:
	if _pause_settings_dialog == null:
		return
	_refresh_pause_keybind_buttons()
	_pause_settings_dialog.popup_centered_ratio(0.6)


func _build_pause_settings_dialog() -> void:
	if _pause_layer == null:
		return
	_pause_settings_dialog = AcceptDialog.new()
	_pause_settings_dialog.title = "Settings"
	_pause_settings_dialog.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_pause_layer.add_child(_pause_settings_dialog)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(520, 360)
	root.add_theme_constant_override("separation", 6)
	_pause_settings_dialog.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 280)
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	for action_name in PAUSE_KEY_ACTIONS.keys():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)

		var action_label := Label.new()
		action_label.text = String(PAUSE_KEY_ACTIONS[action_name])
		action_label.custom_minimum_size = Vector2(220, 0)
		row.add_child(action_label)

		var key_label := Label.new()
		key_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(key_label)

		_pause_keybind_buttons[action_name] = key_label

	_refresh_pause_keybind_buttons()

	# --- Opacity slider ---
	var opacity_row := HBoxContainer.new()
	opacity_row.custom_minimum_size = Vector2(0, 32)
	list.add_child(opacity_row)

	var opacity_label := Label.new()
	opacity_label.text = "Button Opacity"
	opacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_row.add_child(opacity_label)

	var opacity_slider := HSlider.new()
	opacity_slider.min_value = 0.2
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.05
	var cfg := ConfigFile.new()
	cfg.load("user://options.cfg")
	var saved_opacity := float(cfg.get_value("controls", "button_opacity", 0.85))
	opacity_slider.value = saved_opacity
	opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_slider.custom_minimum_size = Vector2(100, 0)
	opacity_row.add_child(opacity_slider)

	var opacity_value_label := Label.new()
	opacity_value_label.text = "%d%%" % (saved_opacity * 100)
	opacity_value_label.custom_minimum_size = Vector2(36, 0)
	opacity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	opacity_row.add_child(opacity_value_label)

	opacity_slider.value_changed.connect(func(v: float) -> void:
		opacity_value_label.text = "%d%%" % (v * 100)
		var c := ConfigFile.new()
		c.load("user://options.cfg")
		c.set_value("controls", "button_opacity", v)
		c.save("user://options.cfg")
		if _player_instance and _player_instance.has_method("update_mobile_button_opacity"):
			_player_instance.call("update_mobile_button_opacity", v)
	)


func _refresh_pause_keybind_buttons() -> void:
	for action_name in _pause_keybind_buttons.keys():
		var key_label := _pause_keybind_buttons[action_name] as Label
		if key_label:
			key_label.text = _pause_describe_action_binding(String(action_name))


func _pause_describe_action_binding(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "Unbound"
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return "Unbound"
	var first := events[0]
	if first is InputEventKey:
		return (first as InputEventKey).as_text_keycode()
	return first.as_text()


func _build_pause_help_panel() -> void:
	if _pause_layer == null:
		return
	_pause_help_panel = PanelContainer.new()
	_pause_help_panel.custom_minimum_size = Vector2(420, 300)
	_pause_help_panel.anchor_left = 0.5
	_pause_help_panel.anchor_top = 0.5
	_pause_help_panel.anchor_right = 0.5
	_pause_help_panel.anchor_bottom = 0.5
	_pause_help_panel.position = Vector2(-210, -150)
	_pause_help_panel.visible = false
	var help_style := StyleBoxFlat.new()
	help_style.bg_color = Color(0.04, 0.04, 0.07, 0.92)
	help_style.border_color = Color(0.78, 0.60, 0.24, 0.7)
	help_style.border_width_left = 2
	help_style.border_width_top = 2
	help_style.border_width_right = 2
	help_style.border_width_bottom = 2
	help_style.corner_radius_top_left = 8
	help_style.corner_radius_top_right = 8
	help_style.corner_radius_bottom_left = 8
	help_style.corner_radius_bottom_right = 8
	help_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	help_style.shadow_size = 6
	help_style.shadow_offset = Vector2(2, 2)
	var help_theme := Theme.new()
	help_theme.set_stylebox("panel", "PanelContainer", help_style)
	_pause_help_panel.theme = help_theme
	_pause_layer.add_child(_pause_help_panel)

	# Close button top right
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.size = Vector2(20, 20)
	close_btn.position = Vector2(396, 6)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_on_pause_help_close)
	_pause_help_panel.add_child(close_btn)

	# Content container
	var content := VBoxContainer.new()
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 16
	content.offset_top = 16
	content.offset_right = -16
	content.offset_bottom = -16
	content.add_theme_constant_override("separation", 6)
	_pause_help_panel.add_child(content)

	# Title
	var title := Label.new()
	title.text = "KEYBINDING HELP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.42, 1.0))
	content.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.78, 0.60, 0.24, 0.4))
	content.add_child(sep)

	_pause_help_label = RichTextLabel.new()
	_pause_help_label.bbcode_enabled = true
	_pause_help_label.fit_content = false
	_pause_help_label.scroll_active = false
	_pause_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_help_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pause_help_label.add_theme_font_size_override("normal_font_size", 14)
	_pause_help_label.add_theme_color_override("default_color", Color(0.88, 0.85, 0.78, 1.0))
	content.add_child(_pause_help_label)

	# Hint at bottom
	var hint := Label.new()
	hint.text = "Press H or X to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
	content.add_child(hint)

	_refresh_pause_help_text()


func _on_pause_help_close() -> void:
	if _pause_help_panel != null:
		_pause_help_panel.visible = false
	if _pause_help_opened_from_gameplay:
		_pause_help_opened_from_gameplay = false
		_resume_game()


func _show_pause_help(from_gameplay := false) -> void:
	if _pause_help_panel == null:
		return
	_pause_help_opened_from_gameplay = from_gameplay
	_refresh_pause_help_text()
	_pause_help_panel.visible = true


func _handle_pause_help_hotkey() -> void:
	if not get_tree().paused:
		_pause_game()
		_show_pause_help(true)
		return
	if _pause_help_panel == null:
		return
	if _pause_help_panel.visible:
		if _pause_help_opened_from_gameplay:
			_pause_help_opened_from_gameplay = false
			_resume_game()
		else:
			_pause_help_panel.visible = false
	else:
		_show_pause_help(false)


func _refresh_pause_help_text() -> void:
	if _pause_help_label == null:
		return
	var lines := []
	for action_name in PAUSE_KEY_ACTIONS.keys():
		lines.append("[color=#D9CC6B]%s[/color] : %s" % [PAUSE_KEY_ACTIONS[action_name], _pause_describe_action_binding(String(action_name))])
	_pause_help_label.text = "\n".join(lines)


func _on_npc_night_started(_queen_position: Vector2) -> void:
	if _night_event_running or _night_skeleton_spawned or _night_skeleton_spawn_pending:
		return
	_night_event_running = true
	_night_skeleton_spawn_pending = true
	_night_player_quest_active = false
	_night_player_quest_engaged = false
	_night_help_line_spoken = false
	_ring_stolen = false
	if _ring_warning_panel:
		_ring_warning_panel.visible = false
	_queen_trick_teleport_index = 0
	_set_prompt_text("")
	_set_objective_text("Defend the princess from skeleton thieves")
	if _npc_instance and _npc_instance.has_method("set_defense_wander_mode"):
		_npc_instance.call("set_defense_wander_mode", true)
	
	# Wait for night transition (darkness + dialogue) to complete before spawning skeleton
	# Darkness takes 10 seconds, plus time for dialogue messages
	if not is_inside_tree():
		return
	var t13 := get_tree()
	if not t13:
		return
	await t13.create_timer(13.0).timeout
	
	# Now spawn skeleton only after complete darkness
	var spawned := _spawn_skeleton_near_queen()
	if spawned == null:
		_night_event_running = false
		return
	await _run_queen_escape_sequence(spawned)
	_night_event_running = false


func _on_intro_exploration_started() -> void:
	_intro_exploration_active = true
	_intro_return_started = false
	_has_torch = false
	_set_objective_text("Quest: Find the Torch and map")
	_show_system_message("Explore: find the Torch, Map.", 5.0)


func _create_intro_hud() -> void:

	_intro_hud_layer = CanvasLayer.new()
	_intro_hud_layer.layer = 60
	add_child(_intro_hud_layer)

	# --- Health hearts: top center ---
	var hearts_bg := ColorRect.new()
	hearts_bg.anchor_left = 0.5
	hearts_bg.anchor_top = 0.0
	hearts_bg.anchor_right = 0.5
	hearts_bg.anchor_bottom = 0.0
	hearts_bg.position = Vector2(-140, 6)
	hearts_bg.size = Vector2(280, 30)
	hearts_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	_intro_hud_layer.add_child(hearts_bg)

	var hearts_row := HBoxContainer.new()
	hearts_row.anchor_left = 0.5
	hearts_row.anchor_top = 0.0
	hearts_row.anchor_right = 0.5
	hearts_row.anchor_bottom = 0.0
	hearts_row.position = Vector2(-135, 8)
	hearts_row.size = Vector2(270, 26)
	hearts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts_row.add_theme_constant_override("separation", 4)
	_intro_hud_layer.add_child(hearts_row)

	_player_hearts.clear()
	for i in range(10):
		var heart := Label.new()
		heart.text = "♥"
		heart.add_theme_font_size_override("font_size", 18)
		heart.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 0.95))
		hearts_row.add_child(heart)
		_player_hearts.append(heart)

	var initial_hp_percent := 100.0
	if _player_instance != null and "current_health" in _player_instance and "max_health" in _player_instance:
		initial_hp_percent = float(_player_instance.current_health) / maxf(1.0, float(_player_instance.max_health)) * 100.0
	_set_player_hearts(initial_hp_percent)

	# --- Quest / objective: top-left ---
	_objective_label = Label.new()
	_objective_label.anchor_left = 0.0
	_objective_label.anchor_top = 0.0
	_objective_label.anchor_right = 0.0
	_objective_label.anchor_bottom = 0.0
	_objective_label.position = Vector2(10, 42)
	_objective_label.size = Vector2(360, 20)
	_objective_label.add_theme_font_size_override("font_size", 13)
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	_objective_label.text = ""
	_intro_hud_layer.add_child(_objective_label)

	# --- Coordinates: top-left below quest ---
	_coordinate_label = Label.new()
	_coordinate_label.anchor_left = 0.0
	_coordinate_label.anchor_top = 0.0
	_coordinate_label.anchor_right = 0.0
	_coordinate_label.anchor_bottom = 0.0
	_coordinate_label.position = Vector2(10, 60)
	_coordinate_label.size = Vector2(200, 16)
	_coordinate_label.add_theme_font_size_override("font_size", 11)
	_coordinate_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	_coordinate_label.text = ""
	_intro_hud_layer.add_child(_coordinate_label)

	# --- Energy bar: bottom-left ---
	var energy_bg := ColorRect.new()
	energy_bg.anchor_left = 0.0
	energy_bg.anchor_top = 1.0
	energy_bg.anchor_right = 0.0
	energy_bg.anchor_bottom = 1.0
	energy_bg.position = Vector2(10, -44)
	energy_bg.size = Vector2(160, 36)
	energy_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	_intro_hud_layer.add_child(energy_bg)

	var energy_label := Label.new()
	energy_label.anchor_left = 0.0
	energy_label.anchor_top = 1.0
	energy_label.anchor_right = 0.0
	energy_label.anchor_bottom = 1.0
	energy_label.position = Vector2(16, -40)
	energy_label.size = Vector2(60, 14)
	energy_label.text = "Energy"
	energy_label.add_theme_font_size_override("font_size", 10)
	energy_label.add_theme_color_override("font_color", Color(0.22, 0.52, 0.98, 1.0))
	_intro_hud_layer.add_child(energy_label)

	_energy_bar = ProgressBar.new()
	_energy_bar.anchor_left = 0.0
	_energy_bar.anchor_top = 1.0
	_energy_bar.anchor_right = 0.0
	_energy_bar.anchor_bottom = 1.0
	_energy_bar.position = Vector2(14, -24)
	_energy_bar.size = Vector2(152, 14)
	_energy_bar.min_value = 0
	_energy_bar.max_value = 100
	_energy_bar.value = 0
	_energy_bar.show_percentage = false
	_energy_bar.add_theme_color_override("fg_color", Color(0.22, 0.52, 0.98, 1.0))
	_energy_bar.add_theme_color_override("bg_color", Color(0.10, 0.10, 0.14, 0.8))
	_intro_hud_layer.add_child(_energy_bar)

	# --- Strength bar: bottom-right ---
	var strength_bg := ColorRect.new()
	strength_bg.anchor_left = 1.0
	strength_bg.anchor_top = 1.0
	strength_bg.anchor_right = 1.0
	strength_bg.anchor_bottom = 1.0
	strength_bg.position = Vector2(-170, -44)
	strength_bg.size = Vector2(160, 36)
	strength_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	_intro_hud_layer.add_child(strength_bg)

	var strength_label := Label.new()
	strength_label.anchor_left = 1.0
	strength_label.anchor_top = 1.0
	strength_label.anchor_right = 1.0
	strength_label.anchor_bottom = 1.0
	strength_label.position = Vector2(-164, -40)
	strength_label.size = Vector2(60, 14)
	strength_label.text = "Strength"
	strength_label.add_theme_font_size_override("font_size", 10)
	strength_label.add_theme_color_override("font_color", Color(0.62, 0.26, 0.86, 1.0))
	_intro_hud_layer.add_child(strength_label)

	_strength_bar = ProgressBar.new()
	_strength_bar.anchor_left = 1.0
	_strength_bar.anchor_top = 1.0
	_strength_bar.anchor_right = 1.0
	_strength_bar.anchor_bottom = 1.0
	_strength_bar.position = Vector2(-166, -24)
	_strength_bar.size = Vector2(152, 14)
	_strength_bar.min_value = 0
	_strength_bar.max_value = 100
	_strength_bar.value = 0
	_strength_bar.show_percentage = false
	_strength_bar.add_theme_color_override("fg_color", Color(0.62, 0.26, 0.86, 1.0))
	_strength_bar.add_theme_color_override("bg_color", Color(0.10, 0.10, 0.14, 0.8))
	_intro_hud_layer.add_child(_strength_bar)

	# --- Potion counts: top-right ---
	var potion_bg := ColorRect.new()
	potion_bg.anchor_left = 1.0
	potion_bg.anchor_top = 0.0
	potion_bg.anchor_right = 1.0
	potion_bg.anchor_bottom = 0.0
	potion_bg.position = Vector2(-240, 6)
	potion_bg.size = Vector2(230, 80)
	potion_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	_intro_hud_layer.add_child(potion_bg)

	var potion_vbox := VBoxContainer.new()
	potion_vbox.anchor_left = 1.0
	potion_vbox.anchor_top = 0.0
	potion_vbox.anchor_right = 1.0
	potion_vbox.anchor_bottom = 0.0
	potion_vbox.position = Vector2(-234, 10)
	potion_vbox.size = Vector2(220, 72)
	potion_vbox.add_theme_constant_override("separation", 4)
	_intro_hud_layer.add_child(potion_vbox)

	_potion_count_labels.clear()
	_add_potion_row(potion_vbox, "health", Color(0.95, 0.82, 0.16, 1.0), "Regeneration")
	_add_potion_row(potion_vbox, "strength", Color(0.62, 0.26, 0.86, 1.0), "Strength Potion")
	_add_potion_row(potion_vbox, "energy", Color(0.22, 0.52, 0.98, 1.0), "Energy Drink")
	_update_potion_inventory()
	_update_resource_bars()

	# Prompt (below panel)
	_prompt_label = Label.new()
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.position = Vector2(-260, 160)
	_prompt_label.size = Vector2(520, 28)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))  # Bright yellow/gold
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_intro_hud_layer.add_child(_prompt_label)

	# Item pickup prompt (floats above items in world)
	_item_prompt_label = Label.new()
	_item_prompt_label.anchor_left = 0.5
	_item_prompt_label.anchor_top = 0.5
	_item_prompt_label.anchor_right = 0.5
	_item_prompt_label.anchor_bottom = 0.5
	_item_prompt_label.size = Vector2(200, 32)
	_item_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	_item_prompt_label.add_theme_font_size_override("font_size", 14)
	_item_prompt_label.visible = false
	_intro_hud_layer.add_child(_item_prompt_label)

	# System message background (below panel)
	_system_message_bg = ColorRect.new()
	_system_message_bg.anchor_left = 0.5
	_system_message_bg.anchor_top = 1.0
	_system_message_bg.anchor_right = 0.5
	_system_message_bg.anchor_bottom = 1.0
	_system_message_bg.position = Vector2(-345, -90)
	_system_message_bg.size = Vector2(690, 56)
	_system_message_bg.color = Color(0.05, 0.05, 0.1, 0.75)
	_system_message_bg.visible = false
	_intro_hud_layer.add_child(_system_message_bg)

	# System message (below panel)
	_system_message_label = Label.new()
	_system_message_label.anchor_left = 0.5
	_system_message_label.anchor_top = 1.0
	_system_message_label.anchor_right = 0.5
	_system_message_label.anchor_bottom = 1.0
	_system_message_label.position = Vector2(-340, -80)
	_system_message_label.size = Vector2(680, 46)
	_system_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_system_message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_system_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_system_message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))  # Bright caption color
	_system_message_label.add_theme_font_size_override("font_size", 18)
	_system_message_label.visible = false
	_intro_hud_layer.add_child(_system_message_label)

	_darkness_hint_label = Label.new()
	_darkness_hint_label.anchor_left = 0.5
	_darkness_hint_label.anchor_top = 0.5
	_darkness_hint_label.anchor_right = 0.5
	_darkness_hint_label.anchor_bottom = 0.5
	_darkness_hint_label.position = Vector2.ZERO
	_darkness_hint_label.size = Vector2(220, 40)
	_darkness_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_darkness_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_darkness_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_darkness_hint_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0, 1.0))
	_darkness_hint_label.visible = false
	_intro_hud_layer.add_child(_darkness_hint_label)

	_ring_warning_panel = PanelContainer.new()
	_ring_warning_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ring_warning_panel.offset_left = -430
	_ring_warning_panel.offset_top = 14
	_ring_warning_panel.offset_right = -16
	_ring_warning_panel.offset_bottom = 104
	_ring_warning_panel.custom_minimum_size = Vector2(370, 74)
	_ring_warning_panel.z_index = 200
	_ring_warning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.45, 0.0, 0.0, 0.96)
	ring_style.border_color = Color(1.0, 0.85, 0.85, 1.0)
	ring_style.border_width_left = 3
	ring_style.border_width_top = 3
	ring_style.border_width_right = 3
	ring_style.border_width_bottom = 3
	ring_style.corner_radius_top_left = 10
	ring_style.corner_radius_top_right = 10
	ring_style.corner_radius_bottom_left = 10
	ring_style.corner_radius_bottom_right = 10
	ring_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	ring_style.shadow_size = 8
	_ring_warning_panel.add_theme_stylebox_override("panel", ring_style)
	_ring_warning_panel.visible = false
	_intro_hud_layer.add_child(_ring_warning_panel)

	_ring_warning_label = Label.new()
	_ring_warning_label.anchor_left = 0.0
	_ring_warning_label.anchor_top = 0.0
	_ring_warning_label.anchor_right = 1.0
	_ring_warning_label.anchor_bottom = 1.0
	_ring_warning_label.offset_left = 10
	_ring_warning_label.offset_top = 8
	_ring_warning_label.offset_right = -10
	_ring_warning_label.offset_bottom = -8
	_ring_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ring_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ring_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ring_warning_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_ring_warning_label.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0, 1.0))
	_ring_warning_label.add_theme_constant_override("outline_size", 2)
	_ring_warning_label.add_theme_font_size_override("font_size", 16)
	_ring_warning_panel.add_child(_ring_warning_label)

	_set_objective_text("")
	_set_prompt_text("")


func _set_player_hearts(health_percent: float) -> void:
	if _player_hearts.is_empty():
		return

	var filled_hearts := int(ceili(clampf(health_percent, 0.0, 100.0) / 10.0))
	for i in range(_player_hearts.size()):
		var heart := _player_hearts[i]
		if heart == null:
			continue
		if i < filled_hearts:
			heart.add_theme_color_override("font_color", Color(0.95, 0.18, 0.22, 1.0))
		else:
			heart.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 0.95))


func _add_potion_row(parent: Node, potion_type: String, tint: Color, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _build_potion_icon_texture(tint)
	row.add_child(icon)

	var count_label := Label.new()
	count_label.text = "%s x0" % label_text
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.9))
	row.add_child(count_label)

	_potion_count_labels[potion_type] = count_label


func _build_potion_icon_texture(tint: Color) -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(16):
		for x in range(16):
			var dx := float(x) - 7.5
			var dy := float(y) - 8.0
			if dx * dx + dy * dy <= 38.0:
				image.set_pixel(x, y, tint)
			if y <= 3 and x >= 6 and x <= 9:
				image.set_pixel(x, y, Color(0.88, 0.88, 0.92, 1.0))
	return ImageTexture.create_from_image(image)


func _update_potion_inventory() -> void:
	if _player_instance == null:
		return
	if not _player_instance.has_method("get_potion_count"):
		return

	var mapping := {
		"health": "Regeneration",
		"strength": "Strength Potion",
		"energy": "Energy Drink",
	}
	for potion_type in mapping.keys():
		var label := _potion_count_labels.get(potion_type, null) as Label
		if label == null:
			continue
		var count := int(_player_instance.call("get_potion_count", potion_type))
		label.text = "%s x%d" % [mapping[potion_type], count]


func _update_resource_bars() -> void:
	if _player_instance == null:
		return
	if _energy_bar != null and _player_instance.has_method("get_energy_percent"):
		_energy_bar.value = float(_player_instance.call("get_energy_percent"))
	if _strength_bar != null and _player_instance.has_method("get_strength_percent"):
		_strength_bar.value = float(_player_instance.call("get_strength_percent"))


func _set_objective_text(text: String) -> void:
	if _objective_label:
		_objective_label.text = text


func _set_prompt_text(text: String) -> void:
	if _prompt_label:
		_prompt_label.text = text


func _show_system_message(text: String, duration := 3.0) -> void:
	if _system_message_label == null:
		return
	
	# Ensure minimum 3 second display time
	var display_duration := maxf(duration, 3.0)
	
	# Add message to queue
	_system_message_queue.append({"text": text, "duration": display_duration})
	
	# Process queue if not already processing
	if not _system_message_processing:
		_process_system_message_queue()


func _process_system_message_queue() -> void:
	if _system_message_queue.is_empty():
		_system_message_processing = false
		return
	
	_system_message_processing = true
	
	# Get next message from queue
	var message = _system_message_queue.pop_front()
	_system_message_label.text = message["text"]
	_system_message_label.visible = true
	if _system_message_bg:
		_system_message_bg.visible = true
	_system_message_time_left = message["duration"]
	_system_message_typing = true
	_system_message_skip_requested = false
	_system_message_label.visible_characters = 0
	
	var message_start_time := Time.get_ticks_msec()
	await _type_system_message()
	
	# Calculate remaining display time
	var elapsed_ms := Time.get_ticks_msec() - message_start_time
	var remaining_time := maxf(0.0, _system_message_time_left - (elapsed_ms / 1000.0))
	
	# Wait for remaining display duration before processing next message
	if remaining_time > 0.0:
		if not is_inside_tree():
			return
		var tmr := get_tree()
		if not tmr:
			return
		await tmr.create_timer(remaining_time).timeout
	
	_system_message_label.visible = false
	if _system_message_bg:
		_system_message_bg.visible = false
	
	# Process next message in queue
	_process_system_message_queue()


func _type_system_message() -> void:
	if _system_message_label == null:
		return
	if not is_inside_tree():
		return

	var total_chars := _system_message_label.get_total_character_count()
	if total_chars <= 0:
		_system_message_label.visible_characters = -1
		_system_message_typing = false
		return

	_system_message_typing = true
	var cps := 60.0  # Characters per second for system messages
	var step_delay := 1.0 / cps

	while _system_message_label.visible_characters < total_chars:
		if _system_message_skip_requested:
			break
		_system_message_label.visible_characters += 1
		if not is_inside_tree():
			return
		var tw := get_tree()
		if not tw:
			return
		await tw.create_timer(step_delay).timeout

	_system_message_label.visible_characters = -1
	_system_message_typing = false
	_system_message_skip_requested = false


func _update_system_message(_delta: float) -> void:
	# Message lifecycle is now handled in _process_system_message_queue
	# This function kept for compatibility but does nothing
	pass


func _show_coordinates() -> void:
	# Coordinates now always display under quest, no need for this function
	pass


func _update_coordinate_display(_delta: float) -> void:
	if _coordinate_label == null or _player_instance == null:
		return

func _update_darkness_hint(_delta: float) -> void:
	if _darkness_hint_label == null or _player_instance == null:
		return

	var is_dark := false
	var canvas_modulate := get_node_or_null("CanvasModulate") as CanvasModulate
	if canvas_modulate and canvas_modulate.visible:
		var c := canvas_modulate.color
		is_dark = maxf(c.r, maxf(c.g, c.b)) <= 0.08
	elif _night_event_running:
		is_dark = true

	var light_on := false
	if _player_instance.has_node("PointLight2D"):
		var light = _player_instance.get_node("PointLight2D") as PointLight2D
		if light:
			light_on = light.visible

	if is_dark and not light_on:
		_darkness_hint_label.text = "Press L to turn on the light"
		var camera := get_viewport().get_camera_2d()
		if camera:
			var viewport_rect := get_viewport().get_visible_rect()
			var screen_pos := (_player_instance.global_position - camera.global_position) / camera.zoom + viewport_rect.size * 0.5
			screen_pos.y -= 62.0
			screen_pos.x -= _darkness_hint_label.size.x * 0.5
			_darkness_hint_label.position = screen_pos
		_darkness_hint_label.visible = true
	else:
		_darkness_hint_label.visible = false
	
	var x = int(_player_instance.global_position.x)
	var y = int(_player_instance.global_position.y)
	_coordinate_label.text = "(%.0f, %.0f)" % [x, y]


func _show_ring_stolen_warning() -> void:
	if _ring_warning_panel == null or _ring_warning_label == null:
		return

	_ring_warning_label.text = "WARNING: RING STOLEN\nEffects: Slowness and teleportation"
	_ring_warning_panel.visible = true
	_ring_warning_time_left = 0.0


func _update_ring_warning(_delta: float) -> void:
	if _ring_warning_panel == null:
		return

	if _ring_stolen:
		_ring_warning_panel.visible = true


func _update_intro_interaction_prompt() -> void:
	if not _intro_exploration_active or _player_instance == null:
		if _item_prompt_label:
			_item_prompt_label.visible = false
		return
	if _item_prompt_label == null:
		return

	var prompt := ""
	var item_world_pos := Vector2.ZERO
	_current_interactable = null
	
	# Check interactable nodes first
	if not _map_read and _map_node and _map_node.is_player_in_range():
		prompt = "Press E\nRead Map"
		item_world_pos = _map_pos
		_current_interactable = _map_node
	elif not _has_torch and _is_player_near(_torch_pos):
		prompt = "Press E\nPick up"
		item_world_pos = _torch_pos

	if prompt == "":
		if _item_prompt_label:
			_item_prompt_label.visible = false
		return

	# Convert world position to screen position
	var camera = get_viewport().get_camera_2d()
	if camera == null:
		if _item_prompt_label:
			_item_prompt_label.visible = false
		return

	var viewport_rect = get_viewport().get_visible_rect()
	var screen_pos = (item_world_pos - camera.global_position) / camera.zoom + viewport_rect.size * 0.5
	screen_pos.y -= 50  # Offset above the item
	
	_item_prompt_label.text = prompt
	_item_prompt_label.position = screen_pos
	_item_prompt_label.visible = true


func _update_intro_return_trigger() -> void:
	if not _intro_exploration_active:
		return
	if not _has_torch or not _map_read:
		return
	if _intro_return_started:
		return
	if _player_instance == null or _npc_instance == null:
		return

	if _player_instance.global_position.distance_to(_npc_instance.global_position) <= 90.0:
		_intro_return_started = true
		_intro_exploration_active = false
		_awaiting_player_near_queen_for_night = false
		_queen_night_countdown_running = false
		_queen_night_countdown_left = 0.0
		_set_prompt_text("")
		_show_system_message("You returned with the Torch and the map of the kingdom.")
		if _npc_instance.has_method("start_return_with_torch_sequence"):
			_npc_instance.call("start_return_with_torch_sequence")
		elif _npc_instance.has_method("start_return_with_sword_sequence"):
			_npc_instance.call("start_return_with_sword_sequence")


func _on_npc_return_briefing_ready() -> void:
	_awaiting_player_near_queen_for_night = true
	_queen_night_countdown_running = true
	_queen_night_countdown_left = queen_wait_to_night_seconds
	_set_objective_text("Quest: Defend the princess from skeleton thieves")
	if _npc_instance and _npc_instance.has_method("set_defense_wander_mode"):
		_npc_instance.call("set_defense_wander_mode", true)
	_set_prompt_text("Night begins in 10 seconds...")
	_show_system_message("The moon eclipse approaches. Night will begin in 10 seconds.", 3.0)


func _update_queen_wait_night_countdown(delta: float) -> void:
	if not _awaiting_player_near_queen_for_night:
		return
	if _npc_instance == null or _player_instance == null:
		return

	_queen_night_countdown_left = maxf(0.0, _queen_night_countdown_left - delta)
	var whole_seconds := int(ceil(_queen_night_countdown_left))
	if whole_seconds > 0:
		_set_prompt_text("Night begins in %d seconds..." % whole_seconds)
	else:
		_set_prompt_text("")

	if _queen_night_countdown_left > 0.0:
		return

	_awaiting_player_near_queen_for_night = false
	_queen_night_countdown_running = false
	_set_prompt_text("")
	if _npc_instance and _npc_instance.has_method("begin_night_countdown_complete"):
		_npc_instance.call("begin_night_countdown_complete")


func _try_intro_interaction() -> void:
	if _player_instance == null:
		return

	# Map interaction
	if _current_interactable and not _map_read and _map_node == _current_interactable:
		if await _map_node.try_interact():
			_map_read = true
			if _player_instance and _player_instance.has_method("set_map_unlocked"):
				_player_instance.call("set_map_unlocked")
			_apply_map_visual_state()
			if _has_torch:
				_set_objective_text("Quest: Return to the princess before midnight")
			else:
				_set_objective_text("Quest: Find the Torch")
			_show_system_message("Map acquired: Shows the layout of the whole place outside the palace.", 5.0)
		return

	# Torch pickup
	if not _has_torch and _is_player_near(_torch_pos):
		_has_torch = true
		if _map_read:
			_set_objective_text("Quest: Return to the princess before midnight")
			_show_system_message("Torch acquired. Now return to the princess.")
		else:
			_set_objective_text("Quest: Read the map")
			_show_system_message("Torch acquired. Now find and read the map.")
		_apply_torch_visual_state()


func _debug_skip_torch_and_map_step() -> void:
	if not _intro_exploration_active:
		return
	if _npc_instance == null:
		return

	_has_torch = true
	_map_read = true
	if _player_instance and _player_instance.has_method("set_map_unlocked"):
		_player_instance.call("set_map_unlocked")
	_intro_exploration_active = false
	_intro_return_started = true
	_apply_torch_visual_state()
	_apply_map_visual_state()
	_set_prompt_text("")
	_set_objective_text("Quest: Defend the princess from skeleton thieves")
	_show_system_message("Debug: Skipped Torch/Map return step.", 2.0)

	if _npc_instance.has_method("start_return_with_torch_sequence"):
		_npc_instance.call("start_return_with_torch_sequence")
	elif _npc_instance.has_method("start_return_with_sword_sequence"):
		_npc_instance.call("start_return_with_sword_sequence")


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


func _apply_map_visual_state() -> void:
	if _map_node == null:
		return
	if _map_read:
		_map_node.queue_free()
		_map_node = null
		if _current_interactable != null:
			_current_interactable = null


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
	_apply_map_visual_state()
	



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


func _spawn_skeleton_near_queen() -> Node2D:
	if _night_skeleton_spawned or skeleton_scene == null:
		_night_skeleton_spawn_pending = false
		return null

	var skeleton := skeleton_scene.instantiate() as Node2D
	if skeleton == null:
		_night_skeleton_spawn_pending = false
		return null

	skeleton.name = "NightSkeleton"
	skeleton.global_position = skeleton_night_spawn_position
	add_child(skeleton)
	_connect_skeleton_ring_signal(skeleton)
	_night_skeleton_instance = skeleton
	_night_skeleton_spawned = true
	_night_skeleton_spawn_pending = false
	return skeleton


func _connect_skeleton_ring_signal(skeleton: Node) -> void:
	if skeleton == null:
		return
	if skeleton.has_signal("ring_stolen") and not skeleton.is_connected("ring_stolen", Callable(self, "_on_skeleton_ring_stolen")):
		skeleton.connect("ring_stolen", Callable(self, "_on_skeleton_ring_stolen"))
	if skeleton.has_signal("requested_backup") and not skeleton.is_connected("requested_backup", Callable(self, "_on_skeleton_requested_backup")):
		skeleton.connect("requested_backup", Callable(self, "_on_skeleton_requested_backup"))


func _on_skeleton_requested_backup(_skeleton_position: Vector2) -> void:
	if _npc_instance == null or skeleton_scene == null:
		return
	if not is_instance_valid(_npc_instance):
		return

	var backup := skeleton_scene.instantiate() as Node2D
	if backup == null:
		return

	var npc_pos := _npc_instance.global_position
	var offset := Vector2(randf_range(-backup_spawn_radius, backup_spawn_radius), randf_range(-backup_spawn_radius, backup_spawn_radius))
	backup.global_position = npc_pos + offset
	backup.name = "BackupSkeleton_%d" % randi()
	add_child(backup)
	_connect_skeleton_ring_signal(backup)

	if backup.has_method("set_forced_target"):
		backup.call("set_forced_target", _npc_instance, true, true)

	_show_system_message("A backup skeleton appeared near the princess!", 3.0)


func _run_queen_escape_sequence(skeleton: Node2D) -> void:
	if _npc_instance == null or skeleton == null:
		return
	if _npc_instance.has_method("set_defense_wander_mode"):
		_npc_instance.call("set_defense_wander_mode", true)

	var escape_target := randi_range(maxi(1, queen_escape_count_min), maxi(1, queen_escape_count_max))
	if skeleton.has_method("set_forced_target"):
		skeleton.call("set_forced_target", _npc_instance, false, true)

	var escapes_done := 0
	while escapes_done < escape_target:
		if _ring_stolen:
			break
		var got_close := await _wait_for_skeleton_near_queen(skeleton, 8.0)
		if not got_close:
			break

		await _teleport_queen_away_from_skeleton(skeleton)
		escapes_done += 1

		if not _night_help_line_spoken and escapes_done >= 1:
			_night_help_line_spoken = true
			_show_system_message("Princess: The ring's power is fading... Come protect me!", 3.0)

		if not is_inside_tree():
			return
		var tw04 := get_tree()
		if not tw04:
			return
		await tw04.create_timer(0.4).timeout

	_night_player_quest_active = true
	_set_objective_text("Quest: Go near the skeleton and protect the princess")
	_show_system_message("Approach the skeleton.", 2.5)


func _wait_for_skeleton_near_queen(skeleton: Node2D, timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if skeleton == null or not is_instance_valid(skeleton) or _npc_instance == null:
			return false
		if skeleton.global_position.distance_to(_npc_instance.global_position) <= queen_escape_trigger_distance:
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return false


func _teleport_queen_away_from_skeleton(skeleton: Node2D) -> void:
	if _npc_instance == null or skeleton == null:
		return
	if queen_trick_teleport_points.is_empty():
		return

	var target := queen_trick_teleport_points[_queen_trick_teleport_index % queen_trick_teleport_points.size()]
	_queen_trick_teleport_index += 1

	var npc_sprite := _npc_instance.get_node_or_null("AnimatedSprite2D2") as AnimatedSprite2D
	if npc_sprite:
		npc_sprite.visible = false
	if not is_inside_tree():
		return
	var tw008 := get_tree()
	if not tw008:
		return
	await tw008.create_timer(0.08).timeout
	_npc_instance.global_position = target
	if npc_sprite:
		npc_sprite.visible = true
	
	_show_system_message("Princess teleported away.", 1.5)


func _update_night_player_quest_trigger() -> void:
	if not _night_player_quest_active:
		return
	if _player_instance == null:
		return
	if _night_skeleton_instance == null or not is_instance_valid(_night_skeleton_instance):
		return

	# Track time since quest started
	_night_quest_wait_time += get_process_delta_time()

	var player_near = _player_instance.global_position.distance_to(_night_skeleton_instance.global_position) <= player_skeleton_engage_distance

	if player_near:
		_night_player_quest_engaged = true
		_set_objective_text("Survive the skeleton attack")
		_show_system_message("Skeleton teleported you near it.", 2.0)
		if _night_skeleton_instance != null and is_instance_valid(_night_skeleton_instance) and _night_skeleton_instance.has_method("set_forced_target"):
			_night_skeleton_instance.call("set_forced_target", _player_instance, true, true)
		_night_quest_wait_time = 0.0
		# Skeleton taunt and attack
		if not is_inside_tree():
			return
		var tw07 := get_tree()
		if not tw07:
			return
		await tw07.create_timer(0.7).timeout
		_show_system_message("Skeleton: I got the ring, and I\'m leaving!", 2.0)
		if not is_inside_tree():
			return
		var tw12 := get_tree()
		if not tw12:
			return
		await tw12.create_timer(1.2).timeout
		if _night_skeleton_instance != null and is_instance_valid(_night_skeleton_instance) and _night_skeleton_instance.has_method("_try_attack_player"):
			_night_skeleton_instance.call("_try_attack_player")
		return

	# If player does not approach after 7 seconds, skeleton teleports player and taunts
	if _night_quest_wait_time > 7.0 and _night_skeleton_instance != null and is_instance_valid(_night_skeleton_instance):
		var skel_pos = _night_skeleton_instance.global_position
		var offset = Vector2(40, 0)
		_player_instance.global_position = skel_pos + offset
		_show_system_message("Skeleton: I got the ring, and I'm leaving!", 2.0)
		if not is_inside_tree():
			return
		var tw12b := get_tree()
		if not tw12b:
			return
		await tw12b.create_timer(1.2).timeout
		if _night_skeleton_instance != null and is_instance_valid(_night_skeleton_instance) and _night_skeleton_instance.has_method("_try_attack_player"):
			_night_skeleton_instance.call("_try_attack_player")
		_night_quest_wait_time = 0.0


func _create_death_overlay() -> void:
	_death_overlay_layer = CanvasLayer.new()
	_death_overlay_layer.layer = 120
	_death_overlay_layer.visible = false
	add_child(_death_overlay_layer)

	_death_overlay_fade = ColorRect.new()
	_death_overlay_fade.anchor_left = 0.0
	_death_overlay_fade.anchor_top = 0.0
	_death_overlay_fade.anchor_right = 1.0
	_death_overlay_fade.anchor_bottom = 1.0
	_death_overlay_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_death_overlay_layer.add_child(_death_overlay_fade)

	# "YOU DIED" label
	_death_overlay_you_died_label = Label.new()
	_death_overlay_you_died_label.anchor_left = 0.5
	_death_overlay_you_died_label.anchor_top = 0.5
	_death_overlay_you_died_label.anchor_right = 0.5
	_death_overlay_you_died_label.anchor_bottom = 0.5
	_death_overlay_you_died_label.position = Vector2(-150, -50)
	_death_overlay_you_died_label.size = Vector2(300, 100)
	_death_overlay_you_died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_overlay_you_died_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_overlay_you_died_label.add_theme_font_size_override("font_size", 58)
	_death_overlay_you_died_label.add_theme_color_override("font_color", Color(0.85, 0.12, 0.12, 1.0))
	_death_overlay_you_died_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_death_overlay_you_died_label.add_theme_constant_override("shadow_offset_x", 2)
	_death_overlay_you_died_label.add_theme_constant_override("shadow_offset_y", 2)
	_death_overlay_you_died_label.text = "YOU DIED"
	_death_overlay_you_died_label.visible = false
	_death_overlay_layer.add_child(_death_overlay_you_died_label)

	# Respawn button
	_death_overlay_respawn_button = Button.new()
	_death_overlay_respawn_button.anchor_left = 0.5
	_death_overlay_respawn_button.anchor_top = 0.5
	_death_overlay_respawn_button.anchor_right = 0.5
	_death_overlay_respawn_button.anchor_bottom = 0.5
	_death_overlay_respawn_button.position = Vector2(-80, 20)
	_death_overlay_respawn_button.size = Vector2(160, 50)
	_death_overlay_respawn_button.text = "Try Again"
	_death_overlay_respawn_button.visible = false
	_death_overlay_respawn_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_death_overlay_respawn_button.pressed.connect(_on_respawn_button_pressed)
	_death_overlay_layer.add_child(_death_overlay_respawn_button)

	_death_overlay_logo = Label.new()
	_death_overlay_logo.anchor_left = 0.5
	_death_overlay_logo.anchor_top = 0.35
	_death_overlay_logo.anchor_right = 0.5
	_death_overlay_logo.anchor_bottom = 0.35
	_death_overlay_logo.position = Vector2(-200, 0)
	_death_overlay_logo.size = Vector2(400, 60)
	_death_overlay_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_overlay_logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_overlay_logo.add_theme_font_size_override("font_size", 38)
	_death_overlay_logo.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55, 1.0))
	_death_overlay_logo.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_death_overlay_logo.add_theme_constant_override("shadow_offset_x", 2)
	_death_overlay_logo.add_theme_constant_override("shadow_offset_y", 2)
	_death_overlay_logo.text = "The Royal Guard"
	_death_overlay_logo.visible = false
	_death_overlay_layer.add_child(_death_overlay_logo)

	_death_overlay_loading = ProgressBar.new()
	_death_overlay_loading.anchor_left = 0.5
	_death_overlay_loading.anchor_top = 0.5
	_death_overlay_loading.anchor_right = 0.5
	_death_overlay_loading.anchor_bottom = 0.5
	_death_overlay_loading.position = Vector2(-150, 40)
	_death_overlay_loading.size = Vector2(300, 6)
	_death_overlay_loading.min_value = 0.0
	_death_overlay_loading.max_value = 100.0
	_death_overlay_loading.value = 0.0
	_death_overlay_loading.show_percentage = false
	_death_overlay_loading.visible = false
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.2, 0.18, 0.12, 0.6)
	bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3
	bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	_death_overlay_loading.add_theme_stylebox_override("background", bar_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.78, 0.55, 0.9)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_death_overlay_loading.add_theme_stylebox_override("fill", fill_style)
	_death_overlay_layer.add_child(_death_overlay_loading)


func _on_player_died() -> void:
	if _death_sequence_started:
		return
	_run_death_sequence()


func _run_death_sequence() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true

	# Clear UI and pause
	_set_prompt_text("")
	_set_objective_text("")
	# Clear system message and dialogue
	if _system_message_label:
		_system_message_label.visible = false
	if _system_message_bg:
		_system_message_bg.visible = false
	# Clear NPC dialogue if visible
	if _npc_instance and _npc_instance.has_method("_clear_dialogue"):
		_npc_instance.call("_clear_dialogue")
	
	if _player_instance and _player_instance.has_method("set_controls_enabled"):
		_player_instance.call("set_controls_enabled", false)
	
	# Pause the game
	get_tree().paused = true
	
	# Fade to black and show YOU DIED with respawn button
	if _death_overlay_layer == null:
		_create_death_overlay()
	_death_overlay_layer.visible = true
	_death_overlay_logo.visible = false
	_death_overlay_loading.visible = false
	_death_overlay_respawn_button.visible = false
	_death_overlay_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_death_overlay_you_died_label.visible = false

	# Cinematic fade-in: dark red tint then YOU DIED text
	if is_inside_tree():
		var twd2 := get_tree()
		if twd2:
			# Dark red tint fades in first
			var tint_tween := create_tween()
			tint_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tint_tween.set_trans(Tween.TRANS_CUBIC)
			tint_tween.tween_property(_death_overlay_fade, "color", Color(0.12, 0.0, 0.0, 0.75), 0.8)
			await tint_tween.finished

			# Show YOU DIED text
			_death_overlay_you_died_label.visible = true
			_death_overlay_you_died_label.modulate.a = 0.0
			var text_tween := create_tween()
			text_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			text_tween.tween_property(_death_overlay_you_died_label, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
			await text_tween.finished

			# Hold for a moment
			await twd2.create_timer(1.5, true).timeout

			# Fade to full black
			var fade_tween := create_tween()
			fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			fade_tween.set_trans(Tween.TRANS_LINEAR)
			fade_tween.tween_property(_death_overlay_fade, "color", Color(0.0, 0.0, 0.0, 1.0), death_black_fade_seconds)
			await fade_tween.finished
	
	# Resume game for loading sequence
	get_tree().paused = false
	
	# At full black, switch to loading screen.
	_death_overlay_you_died_label.visible = false
	_death_overlay_respawn_button.visible = false
	_death_overlay_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	
	_death_overlay_logo.visible = true
	_death_overlay_loading.visible = true
	
	var elapsed := 0.0
	while elapsed < death_loading_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var progress := clampf((elapsed / maxf(0.01, death_loading_seconds)) * 100.0, 0.0, 100.0)
		_death_overlay_loading.value = progress

	get_tree().change_scene_to_file(post_death_scene)


func _on_respawn_button_pressed() -> void:
	_death_respawn_pressed.emit()


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
