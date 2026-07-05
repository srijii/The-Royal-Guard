extends Node2D

@export var player_spawn_offset := Vector2.ZERO
@export var player_scale := Vector2(1.5, 1.5)
@export var spawn_cell_padding := Vector2i(2, 2)
@export var camera_zoom := Vector2(2.8, 2.8)
@export var boss_player_hearts := 10
@export var respawn_delay_seconds := 1.0
@export var end_fade_seconds := 1.8
@export var potion_spawn_interval := 10.0
@export var max_potions_per_type := 2

var _player: Node2D = null
var _player_hearts: Array[Label] = []
var _player_coords_label: Label = null
var _energy_bar: ProgressBar = null
var _strength_bar: ProgressBar = null
var _potion_count_labels: Dictionary = {}
var _quest_label: Label = null
var _tutorial_attack_label: Label = null
var _tutorial_potions_label: Label = null
var _tutorial_sprint_label: Label = null
var _respawn_pending := false
var _ending_started := false
var _death_screen_visible := false
var _ending_layer: CanvasLayer = null
var _ending_fade_rect: ColorRect = null
var _ending_label: Label = null
var _ending_menu_button: Button = null
var _death_layer: CanvasLayer = null
var _death_panel: PanelContainer = null
var _death_respawn_button: Button = null

var _pause_layer: CanvasLayer = null
var _pause_panel: PanelContainer = null
var _is_paused := false

var _drop_bounding_box: Rect2 = Rect2(40, 57, 840, 278)
var _active_spell: Node = null
var _spell_spawn_cooldown: float = 6.0
var _spell_lifetime: float = 6.0
var _dizziness_warning_label: Label = null
var _active_potion_drops: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("final_boss_controller")
	var tilemap := get_node_or_null("TileMap") as TileMap
	var player := get_node_or_null("player") as Node2D
	if tilemap == null or player == null:
		return
	_player = player
	_connect_miko_ring_signal()
	_configure_player_for_final_boss(player)
	_setup_life_ui()
	_setup_death_ui()
	_setup_ending_ui()
	_create_pause_menu()
	_spawn_starting_potions()
	_update_life_ui()

	var map_rect := _get_tilemap_world_rect(tilemap)
	var has_valid_map_rect := map_rect.size.x > 0.0 and map_rect.size.y > 0.0

	player.global_position = _get_spawn_world_position(tilemap, player_spawn_offset)
	player.scale = player_scale
	player.z_as_relative = false
	player.z_index = 50
	tilemap.z_as_relative = false
	tilemap.z_index = -10
	if player is CanvasItem:
		(player as CanvasItem).visible = true
	var player_sprite := player.get_node_or_null("AnimatedSprite2D") as CanvasItem
	if player_sprite != null:
		player_sprite.visible = true

	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if not has_valid_map_rect:
		return

	# Use a tighter gameplay camera and clamp to map bounds.
	cam.top_level = false
	cam.enabled = true
	cam.make_current()
	cam.position_smoothing_enabled = false
	cam.limit_enabled = true
	cam.zoom = camera_zoom
	cam.limit_left = int(round(map_rect.position.x))
	cam.limit_top = int(round(map_rect.position.y))
	cam.limit_right = int(round(map_rect.position.x + map_rect.size.x))
	cam.limit_bottom = int(round(map_rect.position.y + map_rect.size.y))
	player.set("camera_zoom", cam.zoom)


func _process(_delta: float) -> void:
	if _player == null:
		return
	_update_life_ui()
	_update_hud()
	_update_dizziness_warning()


func _configure_player_for_final_boss(player: Node2D) -> void:
	var max_health: int = maxi(10, boss_player_hearts * 10)
	player.set("max_health", max_health)
	player.set("current_health", max_health)

	if player.has_method("get"):
		var max_energy_value := float(player.get("max_energy"))
		player.set("_energy_value", max_energy_value)

	var on_died := Callable(self, "_on_player_died")
	if player.has_signal("died") and not player.is_connected("died", on_died):
		player.connect("died", on_died)

	_setup_potion_spawner()
	# _setup_spell_spawner() — disabled: only potions should drop


func _setup_life_ui() -> void:
	var hud := get_node_or_null("BossHud") as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = "BossHud"
		hud.layer = 100
		add_child(hud)

	# --- Health hearts: top center ---
	var hearts_bg := ColorRect.new()
	hearts_bg.anchor_left = 0.5
	hearts_bg.anchor_top = 0.0
	hearts_bg.anchor_right = 0.5
	hearts_bg.anchor_bottom = 0.0
	hearts_bg.position = Vector2(-140, 6)
	hearts_bg.size = Vector2(280, 30)
	hearts_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud.add_child(hearts_bg)

	var hearts_row := hud.get_node_or_null("HeartsRow") as HBoxContainer
	if hearts_row == null:
		hearts_row = HBoxContainer.new()
		hearts_row.name = "HeartsRow"
		hearts_row.anchor_left = 0.5
		hearts_row.anchor_top = 0.0
		hearts_row.anchor_right = 0.5
		hearts_row.anchor_bottom = 0.0
		hearts_row.position = Vector2(-135, 8)
		hearts_row.size = Vector2(270, 26)
		hearts_row.alignment = BoxContainer.ALIGNMENT_CENTER
		hearts_row.add_theme_constant_override("separation", 4)
		hud.add_child(hearts_row)

	_player_hearts.clear()
	for i in range(boss_player_hearts):
		var heart := Label.new()
		heart.text = "♥"
		heart.add_theme_font_size_override("font_size", 18)
		heart.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 0.95))
		hearts_row.add_child(heart)
		_player_hearts.append(heart)

	# --- Coordinates: top-left ---
	_player_coords_label = Label.new()
	_player_coords_label.anchor_left = 0.0
	_player_coords_label.anchor_top = 0.0
	_player_coords_label.anchor_right = 0.0
	_player_coords_label.anchor_bottom = 0.0
	_player_coords_label.position = Vector2(10, 42)
	_player_coords_label.size = Vector2(200, 16)
	_player_coords_label.text = "Pos: (0, 0)"
	_player_coords_label.add_theme_font_size_override("font_size", 11)
	_player_coords_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	hud.add_child(_player_coords_label)

	# --- Energy bar: bottom-left ---
	var energy_bg := ColorRect.new()
	energy_bg.anchor_left = 0.0
	energy_bg.anchor_top = 1.0
	energy_bg.anchor_right = 0.0
	energy_bg.anchor_bottom = 1.0
	energy_bg.position = Vector2(10, -44)
	energy_bg.size = Vector2(160, 36)
	energy_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud.add_child(energy_bg)

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
	hud.add_child(energy_label)

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
	hud.add_child(_energy_bar)

	# --- Strength bar: bottom-right ---
	var strength_bg := ColorRect.new()
	strength_bg.anchor_left = 1.0
	strength_bg.anchor_top = 1.0
	strength_bg.anchor_right = 1.0
	strength_bg.anchor_bottom = 1.0
	strength_bg.position = Vector2(-170, -44)
	strength_bg.size = Vector2(160, 36)
	strength_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud.add_child(strength_bg)

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
	hud.add_child(strength_label)

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
	hud.add_child(_strength_bar)

	# --- Potions: top-right ---
	var potion_bg := ColorRect.new()
	potion_bg.anchor_left = 1.0
	potion_bg.anchor_top = 0.0
	potion_bg.anchor_right = 1.0
	potion_bg.anchor_bottom = 0.0
	potion_bg.position = Vector2(-240, 6)
	potion_bg.size = Vector2(230, 80)
	potion_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud.add_child(potion_bg)

	var potion_vbox := VBoxContainer.new()
	potion_vbox.anchor_left = 1.0
	potion_vbox.anchor_top = 0.0
	potion_vbox.anchor_right = 1.0
	potion_vbox.anchor_bottom = 0.0
	potion_vbox.position = Vector2(-234, 10)
	potion_vbox.size = Vector2(220, 72)
	potion_vbox.add_theme_constant_override("separation", 4)
	hud.add_child(potion_vbox)

	_potion_count_labels.clear()
	_add_potion_row(potion_vbox, "health", Color(0.95, 0.82, 0.16, 1.0), "Regeneration")
	_add_potion_row(potion_vbox, "strength", Color(0.62, 0.26, 0.86, 1.0), "Strength Potion")
	_add_potion_row(potion_vbox, "energy", Color(0.22, 0.52, 0.98, 1.0), "Energy Drink")
	_add_potion_row(potion_vbox, "stew", Color(0.85, 0.15, 0.1, 1.0), "Red Stew")

	# --- Quest label: top-left ---
	_quest_label = Label.new()
	_quest_label.anchor_left = 0.0
	_quest_label.anchor_top = 0.0
	_quest_label.anchor_right = 0.0
	_quest_label.anchor_bottom = 0.0
	_quest_label.position = Vector2(10, 60)
	_quest_label.size = Vector2(360, 16)
	_quest_label.add_theme_font_size_override("font_size", 11)
	_quest_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24, 1.0))
	hud.add_child(_quest_label)

	# --- Tutorial labels: bottom center ---
	var tutorial_bg := Panel.new()
	tutorial_bg.anchor_left = 0.5
	tutorial_bg.anchor_top = 1.0
	tutorial_bg.anchor_right = 0.5
	tutorial_bg.anchor_bottom = 1.0
	tutorial_bg.position = Vector2(-260, -66)
	tutorial_bg.size = Vector2(520, 60)
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0.06, 0.08, 0.16, 0.75)
	tstyle.border_width_left = 1
	tstyle.border_width_top = 1
	tstyle.border_width_right = 1
	tstyle.border_width_bottom = 1
	tstyle.border_color = Color(0.85, 0.72, 0.22, 0.8)
	tutorial_bg.add_theme_stylebox_override("panel", tstyle)
	hud.add_child(tutorial_bg)

	_tutorial_attack_label = Label.new()
	_tutorial_attack_label.anchor_left = 0.5
	_tutorial_attack_label.anchor_top = 1.0
	_tutorial_attack_label.anchor_right = 0.5
	_tutorial_attack_label.anchor_bottom = 1.0
	_tutorial_attack_label.position = Vector2(-250, -60)
	_tutorial_attack_label.size = Vector2(500, 16)
	_tutorial_attack_label.add_theme_font_size_override("font_size", 10)
	_tutorial_attack_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.22, 0.9))
	hud.add_child(_tutorial_attack_label)

	_tutorial_potions_label = Label.new()
	_tutorial_potions_label.anchor_left = 0.5
	_tutorial_potions_label.anchor_top = 1.0
	_tutorial_potions_label.anchor_right = 0.5
	_tutorial_potions_label.anchor_bottom = 1.0
	_tutorial_potions_label.position = Vector2(-250, -42)
	_tutorial_potions_label.size = Vector2(500, 16)
	_tutorial_potions_label.add_theme_font_size_override("font_size", 10)
	_tutorial_potions_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.85))
	hud.add_child(_tutorial_potions_label)

	_tutorial_sprint_label = Label.new()
	_tutorial_sprint_label.anchor_left = 0.5
	_tutorial_sprint_label.anchor_top = 1.0
	_tutorial_sprint_label.anchor_right = 0.5
	_tutorial_sprint_label.anchor_bottom = 1.0
	_tutorial_sprint_label.position = Vector2(-250, -24)
	_tutorial_sprint_label.size = Vector2(500, 16)
	_tutorial_sprint_label.add_theme_font_size_override("font_size", 10)
	_tutorial_sprint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.85))
	hud.add_child(_tutorial_sprint_label)

	_refresh_tutorial_text()


func _refresh_tutorial_text() -> void:
	var attack_key := _describe_action_binding("attack")
	var health_key := _describe_action_binding("use_health_potion")
	var strength_key := _describe_action_binding("use_strength_potion")
	var energy_key := _describe_action_binding("use_energy_drink")
	var sprint_key := _describe_action_binding("sprint")

	if _tutorial_attack_label:
		_tutorial_attack_label.text = "Press " + attack_key + " to attack"
	if _tutorial_potions_label:
		_tutorial_potions_label.text = "Potions: " + health_key + " Regen | " + strength_key + " Strength | " + energy_key + " Energy"
	if _tutorial_sprint_label:
		_tutorial_sprint_label.text = "Hold " + sprint_key + " to sprint (uses Energy)"


func _describe_action_binding(action_name: String) -> String:
	var actions := InputMap.action_get_events(action_name)
	for event in actions:
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
	return action_name


func _update_life_ui() -> void:
	if _player_hearts.is_empty() or _player == null:
		return

	var current_health: int = int(_player.get("current_health"))
	var max_health: int = maxi(1, int(_player.get("max_health")))
	var health_percent: float = clampf((float(current_health) / float(max_health)) * 100.0, 0.0, 100.0)
	_set_player_hearts(health_percent)


func _set_player_hearts(health_percent: float) -> void:
	var filled_hearts: int = int(ceili(clampf(health_percent, 0.0, 100.0) / 10.0))
	for i in range(_player_hearts.size()):
		var heart := _player_hearts[i]
		if heart == null:
			continue
		if i < filled_hearts:
			heart.add_theme_color_override("font_color", Color(0.95, 0.18, 0.22, 1.0))
		else:
			heart.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 0.95))


func _update_hud() -> void:
	if _player == null:
		return

	# Coordinates
	if _player_coords_label != null:
		var x := int(round(_player.global_position.x))
		var y := int(round(_player.global_position.y))
		_player_coords_label.text = "Pos: (%d, %d)" % [x, y]

	# Resource bars
	if _energy_bar != null and _player.has_method("get_energy_percent"):
		_energy_bar.value = float(_player.call("get_energy_percent"))
	if _strength_bar != null and _player.has_method("get_strength_percent"):
		_strength_bar.value = float(_player.call("get_strength_percent"))

	# Potion inventory
	_update_potion_inventory()

	# Quest
	if _quest_label != null:
		_quest_label.text = "Quest: Defeat Miko and claim the Princess Ring"


func _update_potion_inventory() -> void:
	if _player == null:
		return
	if not _player.has_method("get_potion_count"):
		return

	for potion_type in _potion_count_labels.keys():
		var label := _potion_count_labels.get(potion_type, null) as Label
		if label == null:
			continue
		var count := int(_player.call("get_potion_count", potion_type))
		label.text = "x%d" % count


func _add_potion_row(parent: VBoxContainer, potion_type: String, tint: Color, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _build_potion_icon_texture(tint)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.9))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "x0"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", tint)
	row.add_child(count_label)

	_potion_count_labels[potion_type] = count_label


func _build_potion_icon_texture(tint: Color) -> Texture2D:
	var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(14):
		for x in range(14):
			var dx := float(x) - 7.0
			var dy := float(y) - 7.0
			var d2 := dx * dx + dy * dy
			if d2 <= 36.0 and d2 >= 9.0:
				image.set_pixel(x, y, tint)
	return ImageTexture.create_from_image(image)


func _create_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "BossPauseLayer"
	_pause_layer.layer = 50
	_pause_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_pause_layer)
	_pause_layer.visible = false

	var overlay := ColorRect.new()
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(overlay)

	_pause_panel = PanelContainer.new()
	_pause_panel.custom_minimum_size = Vector2(320, 200)
	_pause_panel.anchor_left = 0.5
	_pause_panel.anchor_top = 0.5
	_pause_panel.anchor_right = 0.5
	_pause_panel.anchor_bottom = 0.5
	_pause_panel.position = Vector2(-160, -100)
	overlay.add_child(_pause_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.10, 0.18, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.85, 0.72, 0.22, 0.9)
	_pause_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(root)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.22, 1.0))
	root.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	root.add_child(spacer)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(220, 40)
	continue_btn.add_theme_font_size_override("font_size", 18)
	continue_btn.pressed.connect(_on_pause_continue)
	root.add_child(continue_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(220, 40)
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.pressed.connect(_on_pause_main_menu)
	root.add_child(menu_btn)


func _on_pause_continue() -> void:
	_is_paused = false
	if _pause_layer:
		_pause_layer.visible = false
	get_tree().paused = false


func _on_pause_main_menu() -> void:
	_is_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if _ending_started:
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
		return

	if _death_screen_visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var key_event := event as InputEventKey
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.keycode == KEY_SPACE:
				_on_death_respawn_pressed()
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			if _is_paused:
				_on_pause_continue()
			else:
				_is_paused = true
				if _pause_layer:
					_pause_layer.visible = true
				get_tree().paused = true
			get_viewport().set_input_as_handled()


func _spawn_starting_potions() -> void:
	var types := ["health", "strength", "energy"]
	for i in range(2):
		var potion_type: String = types[randi() % types.size()]
		var world_pos := Vector2(
			randf_range(_drop_bounding_box.position.x, _drop_bounding_box.end.x),
			randf_range(_drop_bounding_box.position.y, _drop_bounding_box.end.y)
		)

		var tint: Color
		match potion_type:
			"health": tint = Color(0.9, 0.2, 0.2)
			"strength": tint = Color(0.6, 0.2, 0.9)
			"energy": tint = Color(0.2, 0.5, 0.9)

		_spawn_potion_at(potion_type, tint, world_pos)


func _on_player_died() -> void:
	if _ending_started:
		return
	if _death_screen_visible:
		return
	_death_screen_visible = true
	_show_death_screen()


func _setup_death_ui() -> void:
	var layer := get_node_or_null("DeathLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "DeathLayer"
		layer.layer = 900
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)

	var panel := layer.get_node_or_null("DeathPanel") as PanelContainer
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "DeathPanel"
		panel.anchor_left = 0.0
		panel.anchor_top = 0.0
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = 0.0
		panel.offset_top = 0.0
		panel.offset_right = 0.0
		panel.offset_bottom = 0.0
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.78)
		panel.add_theme_stylebox_override("panel", panel_style)
		layer.add_child(panel)

		var content := VBoxContainer.new()
		content.anchor_left = 0.5
		content.anchor_top = 0.5
		content.anchor_right = 0.5
		content.anchor_bottom = 0.5
		content.offset_left = -220.0
		content.offset_top = -110.0
		content.offset_right = 220.0
		content.offset_bottom = 110.0
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 18)
		panel.add_child(content)

		var title := Label.new()
		title.text = "YOU DIED"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 48)
		title.add_theme_color_override("font_color", Color(0.92, 0.2, 0.2, 1.0))
		content.add_child(title)

		var button := Button.new()
		button.name = "RespawnButton"
		button.text = "Respawn"
		button.custom_minimum_size = Vector2(220, 52)
		button.add_theme_font_size_override("font_size", 24)
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(_on_death_respawn_pressed)
		content.add_child(button)

	_death_layer = layer
	_death_panel = panel
	_death_respawn_button = _find_button_recursive(_death_panel, "RespawnButton")
	if _death_respawn_button != null and not _death_respawn_button.pressed.is_connected(_on_death_respawn_pressed):
		_death_respawn_button.pressed.connect(_on_death_respawn_pressed)
	if _death_layer != null:
		_death_layer.visible = false


func _show_death_screen() -> void:
	if _player != null and _player.has_method("set_controls_enabled"):
		_player.call("set_controls_enabled", false)

	var current := get_tree().current_scene
	if current != null:
		var bodies := current.find_children("*", "CharacterBody2D", true, false)
		for node in bodies:
			if node == _player:
				continue
			if node is CharacterBody2D:
				(node as CharacterBody2D).process_mode = Node.PROCESS_MODE_DISABLED

	if _death_layer != null:
		_death_layer.visible = true
	if _death_respawn_button != null:
		_death_respawn_button.disabled = false
		_death_respawn_button.grab_focus()


func _on_death_respawn_pressed() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	get_tree().change_scene_to_file("res://scene/final boss.tscn")


func _find_button_recursive(root: Node, button_name: String) -> Button:
	if root == null:
		return null
	if root is Button and root.name == button_name:
		return root as Button
	for child in root.get_children():
		var nested := _find_button_recursive(child, button_name)
		if nested != null:
			return nested
	return null


func _connect_miko_ring_signal() -> void:
	var miko: Node = get_node_or_null("miko")
	if miko == null:
		return
	var on_ring := Callable(self, "_on_queen_ring_collected")
	if miko.has_signal("queen_ring_collected") and not miko.is_connected("queen_ring_collected", on_ring):
		miko.connect("queen_ring_collected", on_ring)


func _setup_ending_ui() -> void:
	var layer := get_node_or_null("EndingLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "EndingLayer"
		layer.layer = 1000
		layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		add_child(layer)
	layer.visible = false

	var fade_rect := layer.get_node_or_null("FadeRect") as ColorRect
	if fade_rect == null:
		fade_rect = ColorRect.new()
		fade_rect.name = "FadeRect"
		fade_rect.anchor_left = 0.0
		fade_rect.anchor_top = 0.0
		fade_rect.anchor_right = 1.0
		fade_rect.anchor_bottom = 1.0
		fade_rect.offset_left = 0.0
		fade_rect.offset_top = 0.0
		fade_rect.offset_right = 0.0
		fade_rect.offset_bottom = 0.0
		fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(fade_rect)

	var end_label := layer.get_node_or_null("EndLabel") as Label
	if end_label == null:
		end_label = Label.new()
		end_label.name = "EndLabel"
		end_label.anchor_left = 0.5
		end_label.anchor_top = 0.5
		end_label.anchor_right = 0.5
		end_label.anchor_bottom = 0.5
		end_label.offset_left = -420.0
		end_label.offset_top = -80.0
		end_label.offset_right = 420.0
		end_label.offset_bottom = 20.0
		end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		end_label.add_theme_font_size_override("font_size", 44)
		end_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.1, 1.0))
		end_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		end_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_label.text = "YOU WON!"
		layer.add_child(end_label)

	var menu_button := layer.get_node_or_null("MenuButton") as Button
	if menu_button == null:
		menu_button = Button.new()
		menu_button.name = "MenuButton"
		menu_button.anchor_left = 0.5
		menu_button.anchor_top = 0.5
		menu_button.anchor_right = 0.5
		menu_button.anchor_bottom = 0.5
		menu_button.offset_left = -120.0
		menu_button.offset_top = 50.0
		menu_button.offset_right = 120.0
		menu_button.offset_bottom = 90.0
		menu_button.text = "Title Screen"
		menu_button.modulate = Color(1.0, 1.0, 1.0, 0.0)
		menu_button.pressed.connect(_on_ending_main_menu)
		layer.add_child(menu_button)

	_ending_layer = layer
	_ending_fade_rect = fade_rect
	_ending_label = end_label
	_ending_menu_button = menu_button


func _on_queen_ring_collected() -> void:
	if _ending_started:
		return
	_ending_started = true
	_respawn_pending = true

	if _player != null and _player.has_method("set_controls_enabled"):
		_player.call("set_controls_enabled", false)

	get_tree().paused = true

	if _ending_layer != null:
		_ending_layer.visible = true

	if _ending_label != null:
		_ending_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	if _ending_fade_rect != null:
		var fade_tween := _create_ending_tween()
		fade_tween.tween_property(_ending_fade_rect, "color", Color(0.0, 0.0, 0.0, 1.0), 0.8)

	if _ending_label != null:
		var label_tween := _create_ending_tween()
		label_tween.tween_interval(0.8)
		label_tween.tween_property(_ending_label, "modulate:a", 1.0, 0.8)

	if _ending_menu_button != null:
		var btn_tween := _create_ending_tween()
		btn_tween.tween_interval(2.0)
		btn_tween.tween_property(_ending_menu_button, "modulate:a", 1.0, 0.5)


func _get_spawn_world_position(tilemap: TileMap, spawn_offset: Vector2) -> Vector2:
	var used_rect := tilemap.get_used_rect()
	var tile_size := Vector2i(16, 16)
	if tilemap.tile_set != null:
		tile_size = tilemap.tile_set.tile_size

	if used_rect.size == Vector2i.ZERO:
		return tilemap.global_position + spawn_offset

	var cell := used_rect.position + spawn_cell_padding
	cell.x = clampi(cell.x, used_rect.position.x, used_rect.position.x + used_rect.size.x - 1)
	cell.y = clampi(cell.y, used_rect.position.y, used_rect.position.y + used_rect.size.y - 1)

	var local_spawn := Vector2(
		(cell.x + 0.5) * tile_size.x,
		(cell.y + 0.5) * tile_size.y
	)
	return tilemap.to_global(local_spawn) + spawn_offset


func _get_tilemap_world_rect(tilemap: TileMap) -> Rect2:
	var used_rect := tilemap.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return Rect2(tilemap.global_position, Vector2.ZERO)

	var tile_size := Vector2i(16, 16)
	if tilemap.tile_set != null:
		tile_size = tilemap.tile_set.tile_size

	var top_left_local := Vector2(
		used_rect.position.x * tile_size.x,
		used_rect.position.y * tile_size.y
	)
	var bottom_right_local := Vector2(
		(used_rect.position.x + used_rect.size.x) * tile_size.x,
		(used_rect.position.y + used_rect.size.y) * tile_size.y
	)

	var top_left_world := tilemap.to_global(top_left_local)
	var bottom_right_world := tilemap.to_global(bottom_right_local)

	var min_x := minf(top_left_world.x, bottom_right_world.x)
	var min_y := minf(top_left_world.y, bottom_right_world.y)
	var max_x := maxf(top_left_world.x, bottom_right_world.x)
	var max_y := maxf(top_left_world.y, bottom_right_world.y)

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _on_ending_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


func _create_ending_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _show_dizziness_warning() -> void:
	if _dizziness_warning_label == null:
		var hud := get_node_or_null("BossHud") as CanvasLayer
		if hud == null:
			return
		_dizziness_warning_label = Label.new()
		_dizziness_warning_label.anchor_left = 0.5
		_dizziness_warning_label.anchor_top = 0.5
		_dizziness_warning_label.anchor_right = 0.5
		_dizziness_warning_label.anchor_bottom = 0.5
		_dizziness_warning_label.offset_left = -300.0
		_dizziness_warning_label.offset_top = 80.0
		_dizziness_warning_label.offset_right = 300.0
		_dizziness_warning_label.offset_bottom = 120.0
		_dizziness_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_dizziness_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_dizziness_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_dizziness_warning_label.add_theme_font_size_override("font_size", 16)
		_dizziness_warning_label.add_theme_color_override("font_color", Color(0.95, 0.15, 0.1, 1.0))
		_dizziness_warning_label.text = "You took a suspicious potion! Effects applied: Dizziness"
		hud.add_child(_dizziness_warning_label)
	_dizziness_warning_label.visible = true


func _update_dizziness_warning() -> void:
	if _dizziness_warning_label == null:
		return
	if _player == null or not is_instance_valid(_player):
		_dizziness_warning_label.visible = false
		return
	var is_dizzy: bool = false
	if _player.has_method("is_dizziness_active"):
		is_dizzy = bool(_player.call("is_dizziness_active"))
	_dizziness_warning_label.visible = is_dizzy


func _on_potion_drop_removed() -> void:
	_active_potion_drops = maxi(0, _active_potion_drops - 1)


func _setup_potion_spawner() -> void:
	var timer := Timer.new()
	timer.name = "PotionSpawnTimer"
	timer.wait_time = potion_spawn_interval
	timer.one_shot = false
	timer.timeout.connect(_spawn_arena_potion)
	add_child(timer)
	timer.start()


func _spawn_arena_potion() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if _active_potion_drops >= 2:
		return

	var available_types := []
	for ptype in ["health", "strength", "energy", "stew"]:
		var count := 0
		if _player.has_method("get_potion_count"):
			count = int(_player.call("get_potion_count", ptype))
		if count < max_potions_per_type:
			available_types.append(ptype)

	if available_types.is_empty():
		return

	available_types.shuffle()
	var chosen_type := String(available_types[0])
	var tint := _potion_color(chosen_type)

	var spawn_pos := Vector2(
		randf_range(_drop_bounding_box.position.x, _drop_bounding_box.end.x),
		randf_range(_drop_bounding_box.position.y, _drop_bounding_box.end.y)
	)

	_spawn_potion_at(chosen_type, tint, spawn_pos)


func _spawn_potion_at(potion_type: String, tint: Color, p_position: Vector2) -> void:
	var pickup := Area2D.new()
	pickup.name = "ArenaPotionDrop"
	pickup.global_position = p_position
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

	var potion_sprite := Sprite2D.new()
	potion_sprite.texture = _build_potion_drop_texture(tint)
	potion_sprite.scale = Vector2(0.72, 0.72)
	potion_sprite.z_as_relative = false
	potion_sprite.z_index = 102
	pickup.add_child(potion_sprite)

	var pickup_ref: WeakRef = weakref(pickup)
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup_ref, potion_type))

	add_child(pickup)
	_active_potion_drops += 1
	pickup.tree_exiting.connect(_on_potion_drop_removed)
	call_deferred("_check_potion_auto_collect", pickup, potion_type)

	var base_y := pickup.position.y
	var tween := pickup.create_tween()
	tween.set_loops()
	tween.tween_property(pickup, "position:y", base_y - 5.0, 0.45)
	tween.tween_property(pickup, "position:y", base_y + 5.0, 0.45)


func _on_pickup_body_entered(body: Node, pickup_ref: WeakRef, potion_type: String) -> void:
	var pickup := pickup_ref.get_ref() as Area2D
	if pickup == null or not is_instance_valid(pickup):
		return
	if body == null or not is_instance_valid(body):
		return
	if potion_type == "stew":
		if body.has_method("heal"):
			var cur = body.get("current_health")
			if cur == null:
				cur = 0
			var new_hp: int = maxi(0, int(cur) - 10)
			body.set("current_health", new_hp)
			if new_hp <= 0 and body.has_method("die"):
				body.call("die")
			if body.has_method("start_dizziness"):
				body.call("start_dizziness", 10.0)
			call_deferred("_show_dizziness_warning")
		pickup.queue_free()
	elif body.has_method("add_potion_item"):
		body.call("add_potion_item", potion_type)
		pickup.queue_free()


func _check_potion_auto_collect(pickup: Area2D, potion_type: String) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	await get_tree().physics_frame
	if pickup == null or not is_instance_valid(pickup):
		return
	for body in pickup.get_overlapping_bodies():
		if body != null and is_instance_valid(body):
			if potion_type == "stew":
				if body.has_method("heal"):
					var cur = body.get("current_health")
					if cur == null:
						cur = 0
					var new_hp: int = maxi(0, int(cur) - 10)
					body.set("current_health", new_hp)
					if new_hp <= 0 and body.has_method("die"):
						body.call("die")
					if body.has_method("start_dizziness"):
						body.call("start_dizziness", 10.0)
					call_deferred("_show_dizziness_warning")
				pickup.queue_free()
				return
			elif body.has_method("add_potion_item"):
				body.call("add_potion_item", potion_type)
				pickup.queue_free()
				return


func _potion_color(potion_type: String) -> Color:
	match potion_type:
		"health":
			return Color(0.95, 0.82, 0.16, 1.0)
		"strength":
			return Color(0.62, 0.26, 0.86, 1.0)
		"energy":
			return Color(0.22, 0.52, 0.98, 1.0)
		"stew":
			return Color(0.85, 0.15, 0.1, 1.0)
		_:
			return Color(0.85, 0.85, 0.85, 1.0)


func _build_potion_drop_texture(tint: Color) -> Texture2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var body_color := tint
	var highlight := Color(
		minf(1.0, tint.r + 0.3),
		minf(1.0, tint.g + 0.3),
		minf(1.0, tint.b + 0.3),
		tint.a
	)

	for y in range(4, 20):
		for x in range(4, 20):
			var dx := float(x) - 12.0
			var dy := float(y) - 12.0
			var d2 := dx * dx + dy * dy
			if d2 <= 49.0 and d2 >= 16.0:
				image.set_pixel(x, y, body_color)

	for y in range(6, 12):
		for x in range(8, 16):
			var dx := float(x) - 12.0
			var dy := float(y) - 7.0
			if dx * dx + dy * dy <= 9.0:
				image.set_pixel(x, y, highlight)

	return ImageTexture.create_from_image(image)


func _setup_spell_spawner() -> void:
	var timer := Timer.new()
	timer.name = "SpellSpawnTimer"
	timer.wait_time = _spell_spawn_cooldown
	timer.one_shot = false
	timer.timeout.connect(_try_spawn_spell)
	add_child(timer)
	timer.start()


func _try_spawn_spell() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _active_spell != null and is_instance_valid(_active_spell):
		return

	var spell_types := ["fire", "ice", "lightning"]
	var spell_type: String = spell_types[randi() % 3]
	var tint := _spell_color(spell_type)

	var spawn_pos := Vector2(
		randf_range(_drop_bounding_box.position.x, _drop_bounding_box.end.x),
		randf_range(_drop_bounding_box.position.y, _drop_bounding_box.end.y)
	)

	_spawn_spell_at(spell_type, tint, spawn_pos)


func _spawn_spell_at(spell_type: String, tint: Color, p_position: Vector2) -> void:
	var pickup := Area2D.new()
	pickup.name = "SpellPickup"
	pickup.global_position = p_position
	pickup.monitoring = true
	pickup.monitorable = true
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.z_as_relative = false
	pickup.z_index = 100
	pickup.y_sort_enabled = false

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	pickup.add_child(shape)

	var sprite := Sprite2D.new()
	sprite.texture = _build_spell_pickup_texture(tint)
	sprite.scale = Vector2(0.8, 0.8)
	sprite.z_as_relative = false
	sprite.z_index = 102
	pickup.add_child(sprite)

	var pickup_ref: WeakRef = weakref(pickup)
	pickup.body_entered.connect(_on_spell_pickup_body_entered.bind(pickup_ref, spell_type))

	_active_spell = pickup
	add_child(pickup)

	call_deferred("_check_spell_auto_collect", pickup, spell_type)

	var base_spell_y := pickup.position.y
	var bob_tween := pickup.create_tween()
	bob_tween.set_loops()
	bob_tween.tween_property(pickup, "position:y", base_spell_y - 5.0, 0.45)
	bob_tween.tween_property(pickup, "position:y", base_spell_y + 5.0, 0.45)

	var despawn_timer := Timer.new()
	despawn_timer.wait_time = _spell_lifetime
	despawn_timer.one_shot = true
	despawn_timer.timeout.connect(func() -> void:
		if is_instance_valid(pickup):
			pickup.queue_free()
			if _active_spell == pickup:
				_active_spell = null
	)
	pickup.add_child(despawn_timer)
	despawn_timer.start()


func _on_spell_pickup_body_entered(body: Node, pickup_ref: WeakRef, spell_type: String) -> void:
	var pickup := pickup_ref.get_ref() as Area2D
	if pickup == null or not is_instance_valid(pickup):
		return
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("add_spell_item") and body.has_method("get_spell_count"):
		var current_count := int(body.call("get_spell_count", spell_type))
		if current_count >= 2:
			return
		body.call("add_spell_item", spell_type)
		pickup.queue_free()
		if _active_spell == pickup:
			_active_spell = null


func _check_spell_auto_collect(pickup: Area2D, spell_type: String) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	await get_tree().physics_frame
	if pickup == null or not is_instance_valid(pickup):
		return
	for body in pickup.get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.has_method("add_spell_item"):
			var current_count := int(body.call("get_spell_count", spell_type))
			if current_count < 2:
				body.call("add_spell_item", spell_type)
				pickup.queue_free()
				if _active_spell == pickup:
					_active_spell = null
				return


func _spell_color(spell_type: String) -> Color:
	if spell_type == "fire":
		return Color(1.0, 0.3, 0.1)
	elif spell_type == "ice":
		return Color(0.3, 0.7, 1.0)
	elif spell_type == "lightning":
		return Color(1.0, 1.0, 0.2)
	return Color.WHITE


func _build_spell_pickup_texture(tint: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var cx := 8.0
	var cy := 8.0
	for x in range(16):
		for y in range(16):
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= 6.0:
				img.set_pixel(x, y, tint)
			elif d <= 7.5:
				img.set_pixel(x, y, tint.darkened(0.4))
	var tex := ImageTexture.new()
	tex.set_image(img)
	return tex
