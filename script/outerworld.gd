extends Node2D

const WARDEN_SCENE: PackedScene = preload("res://scene/warden.tscn")
const WIZARD_SCENE: PackedScene = preload("res://scene/wizard.tscn")
const WIZARD_SPAWN_POSITIONS := [
	Vector2(2566, 1565),
	Vector2(2444, 1480),
	Vector2(2270, 1553),
]
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

@export var warden_spawn_positions: Array[Vector2] = [
	Vector2(222, 444),
	Vector2(300, 1200),
	Vector2(850, 1000),
	Vector2(1100, 600),
	Vector2(1111, 30),
	Vector2(1650, 400),
	Vector2(2480, 420),
	Vector2(2644, 1189),
	Vector2(1626, 1477),
	Vector2(1723, 962),
	Vector2(876, 1523)
]
@export var door_trigger_position := Vector2(200.5, -31.0)
@export var door_trigger_size := Vector2(420.0, 96.0)
@export var door_required_keys := 3
@export_file("*.tscn") var door_destination_scene := "res://scene/final boss.tscn"
@export var door_loading_seconds := 3.0

var _player_node: Node2D = null
var _player_hearts: Array[Label] = []
var _player_coords_label: Label = null
var _potion_count_labels: Dictionary = {}
var _wizard_key_count_label: Label = null
var _quest_label: Label = null
var _tutorial_attack_label: Label = null
var _tutorial_potions_label: Label = null
var _tutorial_sprint_label: Label = null
var _energy_bar: ProgressBar = null
var _strength_bar: ProgressBar = null
var _pause_layer: CanvasLayer = null
var _pause_panel: PanelContainer = null
var _pause_help_panel: PanelContainer = null
var _pause_help_label: Label = null
var _pause_help_opened_from_gameplay := false
var _pause_settings_dialog: AcceptDialog = null
var _pause_keybind_buttons: Dictionary = {}
var _frozen_character_modes: Dictionary = {}
var _manual_pause_freeze_active := false
var _death_sequence_started := false
var _door_gate_area: Area2D = null
var _door_hint_layer: CanvasLayer = null
var _door_hint_label: Label = null
var _door_hint_message_serial := 0
var _door_loading_layer: CanvasLayer = null
var _door_loading_title: Label = null
var _door_loading_bar: ProgressBar = null
var _door_transition_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_node = get_node_or_null("player") as Node2D
	if _player_node != null and _player_node.has_signal("died") and not _player_node.is_connected("died", Callable(self, "_on_player_died")):
		_player_node.connect("died", Callable(self, "_on_player_died"))
	_create_door_gate_ui()
	_create_door_gate_area()
	_create_pause_menu()
	_create_health_hud()
	_spawn_starting_wardens()
	_spawn_starting_wizards()
	_update_health_bars()


func _process(_delta: float) -> void:
	if _player_node == null:
		_player_node = get_node_or_null("player") as Node2D
		if _player_node != null and _player_node.has_signal("died") and not _player_node.is_connected("died", Callable(self, "_on_player_died")):
			_player_node.connect("died", Callable(self, "_on_player_died"))
	_update_health_bars()

func _on_player_died() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	if _player_node != null:
		if _player_node is CanvasItem:
			(_player_node as CanvasItem).visible = false
		elif _player_node.has_node("AnimatedSprite2D"):
			var sprite := _player_node.get_node_or_null("AnimatedSprite2D") as CanvasItem
			if sprite:
				sprite.visible = false
	if _pause_layer:
		_pause_layer.visible = false


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


func _create_health_hud() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "OuterworldHUD"
	add_child(hud_layer)

	# --- Health hearts: top center ---
	var hearts_bg := ColorRect.new()
	hearts_bg.anchor_left = 0.5
	hearts_bg.anchor_top = 0.0
	hearts_bg.anchor_right = 0.5
	hearts_bg.anchor_bottom = 0.0
	hearts_bg.position = Vector2(-140, 6)
	hearts_bg.size = Vector2(280, 30)
	hearts_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud_layer.add_child(hearts_bg)

	var hearts_row := HBoxContainer.new()
	hearts_row.anchor_left = 0.5
	hearts_row.anchor_top = 0.0
	hearts_row.anchor_right = 0.5
	hearts_row.anchor_bottom = 0.0
	hearts_row.position = Vector2(-135, 8)
	hearts_row.size = Vector2(270, 26)
	hearts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts_row.add_theme_constant_override("separation", 4)
	hud_layer.add_child(hearts_row)

	_player_hearts.clear()
	for i in range(10):
		var heart := Label.new()
		heart.text = "♥"
		heart.add_theme_font_size_override("font_size", 18)
		heart.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 0.95))
		hearts_row.add_child(heart)
		_player_hearts.append(heart)

	_set_player_hearts(_health_percent(_player_node))

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
	hud_layer.add_child(_player_coords_label)

	# --- Energy bar: bottom-left ---
	var energy_bg := ColorRect.new()
	energy_bg.anchor_left = 0.0
	energy_bg.anchor_top = 1.0
	energy_bg.anchor_right = 0.0
	energy_bg.anchor_bottom = 1.0
	energy_bg.position = Vector2(10, -44)
	energy_bg.size = Vector2(160, 36)
	energy_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud_layer.add_child(energy_bg)

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
	hud_layer.add_child(energy_label)

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
	hud_layer.add_child(_energy_bar)

	# --- Strength bar: bottom-right ---
	var strength_bg := ColorRect.new()
	strength_bg.anchor_left = 1.0
	strength_bg.anchor_top = 1.0
	strength_bg.anchor_right = 1.0
	strength_bg.anchor_bottom = 1.0
	strength_bg.position = Vector2(-170, -44)
	strength_bg.size = Vector2(160, 36)
	strength_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud_layer.add_child(strength_bg)

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
	hud_layer.add_child(strength_label)

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
	hud_layer.add_child(_strength_bar)

	# --- Potions: top-right ---
	var potion_bg := ColorRect.new()
	potion_bg.anchor_left = 1.0
	potion_bg.anchor_top = 0.0
	potion_bg.anchor_right = 1.0
	potion_bg.anchor_bottom = 0.0
	potion_bg.position = Vector2(-240, 6)
	potion_bg.size = Vector2(230, 80)
	potion_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud_layer.add_child(potion_bg)

	var potion_vbox := VBoxContainer.new()
	potion_vbox.anchor_left = 1.0
	potion_vbox.anchor_top = 0.0
	potion_vbox.anchor_right = 1.0
	potion_vbox.anchor_bottom = 0.0
	potion_vbox.position = Vector2(-234, 10)
	potion_vbox.size = Vector2(220, 72)
	potion_vbox.add_theme_constant_override("separation", 4)
	hud_layer.add_child(potion_vbox)

	_potion_count_labels.clear()
	_add_potion_row(potion_vbox, "health", Color(0.95, 0.82, 0.16, 1.0), "Regeneration")
	_add_potion_row(potion_vbox, "strength", Color(0.62, 0.26, 0.86, 1.0), "Strength Potion")
	_add_potion_row(potion_vbox, "energy", Color(0.22, 0.52, 0.98, 1.0), "Energy Drink")

	# --- Wizard key: top-right below potions ---
	var key_bg := ColorRect.new()
	key_bg.anchor_left = 1.0
	key_bg.anchor_top = 0.0
	key_bg.anchor_right = 1.0
	key_bg.anchor_bottom = 0.0
	key_bg.position = Vector2(-240, 90)
	key_bg.size = Vector2(230, 28)
	key_bg.color = Color(0.05, 0.05, 0.08, 0.6)
	hud_layer.add_child(key_bg)

	var key_row := HBoxContainer.new()
	key_row.anchor_left = 1.0
	key_row.anchor_top = 0.0
	key_row.anchor_right = 1.0
	key_row.anchor_bottom = 0.0
	key_row.position = Vector2(-234, 92)
	key_row.size = Vector2(220, 24)
	key_row.add_theme_constant_override("separation", 6)
	hud_layer.add_child(key_row)

	var key_icon := TextureRect.new()
	key_icon.custom_minimum_size = Vector2(16, 16)
	key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	key_icon.texture = _build_potion_icon_texture(Color(0.95, 0.84, 0.24, 1.0))
	key_row.add_child(key_icon)

	_wizard_key_count_label = Label.new()
	_wizard_key_count_label.text = "Wizard Key x0"
	_wizard_key_count_label.add_theme_font_size_override("font_size", 12)
	_wizard_key_count_label.add_theme_color_override("font_color", Color(0.95, 0.84, 0.24, 1.0))
	key_row.add_child(_wizard_key_count_label)

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
	hud_layer.add_child(_quest_label)

	# --- Tutorial labels: bottom center with dark background ---
	var tutorial_bg := ColorRect.new()
	tutorial_bg.anchor_left = 0.5
	tutorial_bg.anchor_top = 1.0
	tutorial_bg.anchor_right = 0.5
	tutorial_bg.anchor_bottom = 1.0
	tutorial_bg.position = Vector2(-210, -138)
	tutorial_bg.size = Vector2(420, 70)
	tutorial_bg.color = Color(0.04, 0.04, 0.06, 0.7)
	hud_layer.add_child(tutorial_bg)

	_tutorial_attack_label = Label.new()
	_tutorial_attack_label.anchor_left = 0.5
	_tutorial_attack_label.anchor_top = 1.0
	_tutorial_attack_label.anchor_right = 0.5
	_tutorial_attack_label.anchor_bottom = 1.0
	_tutorial_attack_label.position = Vector2(-200, -133)
	_tutorial_attack_label.size = Vector2(400, 18)
	_tutorial_attack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_attack_label.add_theme_font_size_override("font_size", 12)
	_tutorial_attack_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	hud_layer.add_child(_tutorial_attack_label)

	_tutorial_potions_label = Label.new()
	_tutorial_potions_label.anchor_left = 0.5
	_tutorial_potions_label.anchor_top = 1.0
	_tutorial_potions_label.anchor_right = 0.5
	_tutorial_potions_label.anchor_bottom = 1.0
	_tutorial_potions_label.position = Vector2(-200, -115)
	_tutorial_potions_label.size = Vector2(400, 18)
	_tutorial_potions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_potions_label.add_theme_font_size_override("font_size", 12)
	_tutorial_potions_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	hud_layer.add_child(_tutorial_potions_label)

	_tutorial_sprint_label = Label.new()
	_tutorial_sprint_label.anchor_left = 0.5
	_tutorial_sprint_label.anchor_top = 1.0
	_tutorial_sprint_label.anchor_right = 0.5
	_tutorial_sprint_label.anchor_bottom = 1.0
	_tutorial_sprint_label.position = Vector2(-200, -97)
	_tutorial_sprint_label.size = Vector2(400, 18)
	_tutorial_sprint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_sprint_label.add_theme_font_size_override("font_size", 12)
	_tutorial_sprint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	hud_layer.add_child(_tutorial_sprint_label)

	_refresh_tutorial_labels()

	_update_potion_inventory()
	_update_resource_bars()



func _update_health_bars() -> void:
	_set_player_hearts(_health_percent(_player_node))

	if _player_coords_label != null and _player_node != null:
		var x := int(round(_player_node.global_position.x))
		var y := int(round(_player_node.global_position.y))
		_player_coords_label.text = "Pos: (%d, %d)" % [x, y]

	_update_potion_inventory()
	_update_resource_bars()
	_refresh_tutorial_labels()


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


func _health_percent(target: Node) -> float:
	if target == null:
		return 0.0
	var current_health = target.get("current_health")
	if current_health == null:
		return 0.0
	var max_value := float(target.get("max_health"))
	if max_value <= 0.0:
		max_value = float(target.get("health"))
	if max_value <= 0.0:
		return 0.0
	return clampf(float(current_health) / max_value * 100.0, 0.0, 100.0)


func _add_potion_row(parent: VBoxContainer, potion_type: String, tint: Color, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _build_potion_icon_texture(tint)
	row.add_child(icon)

	var count_label := Label.new()
	count_label.text = "%s x0" % label_text
	count_label.add_theme_font_size_override("font_size", 12)
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
	if _player_node == null:
		return
	if not _player_node.has_method("get_potion_count"):
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
		var count := int(_player_node.call("get_potion_count", potion_type))
		label.text = "%s x%d" % [mapping[potion_type], count]

	if _wizard_key_count_label != null:
		var key_count := 0
		if _player_node.has_method("get_wizard_key_count"):
			key_count = int(_player_node.call("get_wizard_key_count"))
		_wizard_key_count_label.text = "Wizard Key x%d" % key_count
		if _quest_label != null:
			if key_count < door_required_keys:
				_quest_label.text = "Quest: Get %d keys from the wizards (%d/%d)" % [door_required_keys, mini(key_count, door_required_keys), door_required_keys]
			else:
				_quest_label.text = "Quest: Go through the bottom right door."


func _refresh_tutorial_labels() -> void:
	if _tutorial_attack_label != null:
		_tutorial_attack_label.text = "Tutorial: Press Ctrl to attack"

	if _tutorial_potions_label != null:
		var regen_key := _pause_describe_action_binding("use_health_potion")
		var strength_key := _pause_describe_action_binding("use_strength_potion")
		var energy_key := _pause_describe_action_binding("use_energy_drink")
		_tutorial_potions_label.text = "Tutorial: Potions - %s: Regeneration, %s: Strength, %s: Energy" % [regen_key, strength_key, energy_key]

	if _tutorial_sprint_label != null:
		_tutorial_sprint_label.text = "Tutorial: Hold Shift to sprint (uses Energy)"


func _update_resource_bars() -> void:
	if _player_node == null:
		return
	if _energy_bar != null and _player_node.has_method("get_energy_percent"):
		_energy_bar.value = float(_player_node.call("get_energy_percent"))
	if _strength_bar != null and _player_node.has_method("get_strength_percent"):
		_strength_bar.value = float(_player_node.call("get_strength_percent"))


func _spawn_starting_wardens() -> void:
	if WARDEN_SCENE == null:
		push_warning("Warden scene is not assigned; cannot spawn wardens.")
		return

	for i in range(warden_spawn_positions.size()):
		var warden := WARDEN_SCENE.instantiate() as Node2D
		if warden == null:
			continue

		warden.name = "warden_%d" % i
		warden.global_position = warden_spawn_positions[i]
		add_child(warden)


func _spawn_starting_wizards() -> void:
	if WIZARD_SCENE == null:
		push_warning("Wizard scene is not assigned; cannot spawn wizards.")
		return

	for i in range(WIZARD_SPAWN_POSITIONS.size()):
		var wizard := WIZARD_SCENE.instantiate() as Node2D
		if wizard == null:
			continue

		wizard.name = "wizard_%d" % i
		wizard.global_position = WIZARD_SPAWN_POSITIONS[i]
		add_child(wizard)


func _create_door_gate_area() -> void:
	if _door_gate_area != null:
		return

	var existing := get_node_or_null("OuterworldGateArea") as Area2D
	if existing != null:
		_door_gate_area = existing
		_door_gate_area.position = door_trigger_position
		_door_gate_area.collision_layer = 0
		_door_gate_area.collision_mask = 1

		var existing_shape := _door_gate_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if existing_shape == null:
			existing_shape = CollisionShape2D.new()
			existing_shape.name = "CollisionShape2D"
			_door_gate_area.add_child(existing_shape)

		var existing_rect := existing_shape.shape as RectangleShape2D
		if existing_rect == null:
			existing_rect = RectangleShape2D.new()
			existing_shape.shape = existing_rect
		existing_rect.size = door_trigger_size

		if not _door_gate_area.body_entered.is_connected(_on_door_gate_body_entered):
			_door_gate_area.body_entered.connect(_on_door_gate_body_entered)
		return

	_door_gate_area = Area2D.new()
	_door_gate_area.name = "OuterworldGateArea"
	_door_gate_area.position = door_trigger_position
	_door_gate_area.collision_layer = 0
	_door_gate_area.collision_mask = 1
	add_child(_door_gate_area)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = door_trigger_size
	shape.shape = rect
	_door_gate_area.add_child(shape)

	_door_gate_area.body_entered.connect(_on_door_gate_body_entered)


func _create_door_gate_ui() -> void:
	if _door_hint_layer == null:
		_door_hint_layer = CanvasLayer.new()
		_door_hint_layer.layer = 140
		_door_hint_layer.visible = false
		add_child(_door_hint_layer)

		var hint_panel := PanelContainer.new()
		hint_panel.anchor_left = 0.5
		hint_panel.anchor_top = 0.12
		hint_panel.anchor_right = 0.5
		hint_panel.anchor_bottom = 0.12
		hint_panel.position = Vector2(-210, -20)
		hint_panel.custom_minimum_size = Vector2(420, 40)
		var hint_style := StyleBoxFlat.new()
		hint_style.bg_color = Color(0.08, 0.08, 0.10, 0.9)
		hint_style.border_color = Color(0.92, 0.82, 0.36, 1.0)
		hint_style.border_width_left = 1
		hint_style.border_width_top = 1
		hint_style.border_width_right = 1
		hint_style.border_width_bottom = 1
		hint_panel.add_theme_stylebox_override("panel", hint_style)
		_door_hint_layer.add_child(hint_panel)

		_door_hint_label = Label.new()
		_door_hint_label.anchor_left = 0.0
		_door_hint_label.anchor_top = 0.0
		_door_hint_label.anchor_right = 1.0
		_door_hint_label.anchor_bottom = 1.0
		_door_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_door_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_door_hint_label.add_theme_font_size_override("font_size", 16)
		hint_panel.add_child(_door_hint_label)

	if _door_loading_layer == null:
		_door_loading_layer = CanvasLayer.new()
		_door_loading_layer.layer = 145
		_door_loading_layer.visible = false
		add_child(_door_loading_layer)

		var bg := ColorRect.new()
		bg.anchor_left = 0.0
		bg.anchor_top = 0.0
		bg.anchor_right = 1.0
		bg.anchor_bottom = 1.0
		bg.color = Color(0.0, 0.0, 0.0, 1.0)
		_door_loading_layer.add_child(bg)

		_door_loading_title = Label.new()
		_door_loading_title.anchor_left = 0.5
		_door_loading_title.anchor_top = 0.40
		_door_loading_title.anchor_right = 0.5
		_door_loading_title.anchor_bottom = 0.40
		_door_loading_title.position = Vector2(-260, 0)
		_door_loading_title.size = Vector2(520, 80)
		_door_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_door_loading_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_door_loading_title.add_theme_font_size_override("font_size", 42)
		_door_loading_title.text = "IN SEARCH OF THE RING"
		_door_loading_layer.add_child(_door_loading_title)

		_door_loading_bar = ProgressBar.new()
		_door_loading_bar.anchor_left = 0.5
		_door_loading_bar.anchor_top = 0.62
		_door_loading_bar.anchor_right = 0.5
		_door_loading_bar.anchor_bottom = 0.62
		_door_loading_bar.position = Vector2(-220, 0)
		_door_loading_bar.size = Vector2(440, 24)
		_door_loading_bar.min_value = 0.0
		_door_loading_bar.max_value = 100.0
		_door_loading_bar.value = 0.0
		_door_loading_bar.show_percentage = false
		_door_loading_layer.add_child(_door_loading_bar)


func _on_door_gate_body_entered(body: Node) -> void:
	if _door_transition_active:
		return
	if not _is_player_body(body):
		return

	var key_count := _get_wizard_key_count()
	if key_count < door_required_keys:
		_show_door_hint("Bring %d keys to open the door." % door_required_keys)
		return

	_start_door_transition()


func _is_player_body(body: Node) -> bool:
	if body == null:
		return false
	if body == _player_node:
		return true
	if body.is_in_group("player"):
		return true
	return body.name.to_lower() == "player"


func _get_wizard_key_count() -> int:
	if _player_node == null:
		return 0
	if _player_node.has_method("get_wizard_key_count"):
		return int(_player_node.call("get_wizard_key_count"))
	return 0


func _show_door_hint(message: String) -> void:
	if _door_hint_layer == null or _door_hint_label == null:
		return
	_door_hint_message_serial += 1
	var serial := _door_hint_message_serial
	_door_hint_label.text = message
	_door_hint_layer.visible = true
	_hide_door_hint_after_delay(serial)


func _hide_door_hint_after_delay(serial: int) -> void:
	await get_tree().create_timer(1.6).timeout
	if serial != _door_hint_message_serial:
		return
	if _door_transition_active:
		return
	if _door_hint_layer != null:
		_door_hint_layer.visible = false


func _start_door_transition() -> void:
	if _door_transition_active:
		return
	_door_transition_active = true

	if get_tree().paused:
		_resume_game()
	_set_characters_frozen(true)

	if _door_hint_layer != null:
		_door_hint_layer.visible = false

	_run_door_transition_sequence()


func _run_door_transition_sequence() -> void:
	if _door_loading_layer != null:
		_door_loading_layer.visible = true
	if _door_loading_bar != null:
		_door_loading_bar.value = 0.0

	var elapsed := 0.0
	while elapsed < door_loading_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if _door_loading_bar != null:
			var progress := clampf((elapsed / maxf(0.01, door_loading_seconds)) * 100.0, 0.0, 100.0)
			_door_loading_bar.value = progress

	if door_destination_scene == "" or not ResourceLoader.exists(door_destination_scene, "PackedScene"):
		if _door_loading_layer != null:
			_door_loading_layer.visible = false
		_set_characters_frozen(false)
		_door_transition_active = false
		_show_door_hint("Door destination scene is missing.")
		return

	get_tree().change_scene_to_file(door_destination_scene)


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


func _go_to_main_menu() -> void:
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


func _refresh_pause_keybind_buttons() -> void:
	for action_name in _pause_keybind_buttons.keys():
		var key_label := _pause_keybind_buttons[action_name] as Label
		if key_label:
			key_label.text = _pause_describe_action_binding(String(action_name))
	_refresh_tutorial_labels()


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
	_pause_help_panel.custom_minimum_size = Vector2(420, 280)
	_pause_help_panel.anchor_left = 0.5
	_pause_help_panel.anchor_top = 0.5
	_pause_help_panel.anchor_right = 0.5
	_pause_help_panel.anchor_bottom = 0.5
	_pause_help_panel.position = Vector2(-210, -140)
	_pause_help_panel.visible = false
	var help_style := StyleBoxFlat.new()
	help_style.bg_color = Color(0.05, 0.05, 0.08, 1.0)
	help_style.border_color = Color(0.95, 0.88, 0.42, 1.0)
	help_style.border_width_left = 1
	help_style.border_width_top = 1
	help_style.border_width_right = 1
	help_style.border_width_bottom = 1
	var help_theme := Theme.new()
	help_theme.set_stylebox("panel", "PanelContainer", help_style)
	_pause_help_panel.theme = help_theme
	_pause_layer.add_child(_pause_help_panel)

	_pause_help_label = Label.new()
	_pause_help_label.anchor_left = 0.0
	_pause_help_label.anchor_top = 0.0
	_pause_help_label.anchor_right = 1.0
	_pause_help_label.anchor_bottom = 1.0
	_pause_help_label.offset_left = 12
	_pause_help_label.offset_top = 12
	_pause_help_label.offset_right = -12
	_pause_help_label.offset_bottom = -12
	_pause_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_help_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_pause_help_panel.add_child(_pause_help_label)
	_refresh_pause_help_text()


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
	var lines := ["Keybinding Help"]
	for action_name in PAUSE_KEY_ACTIONS.keys():
		lines.append("%s : %s" % [PAUSE_KEY_ACTIONS[action_name], _pause_describe_action_binding(String(action_name))])
	lines.append("Press H to hide/show this help")
	_pause_help_label.text = "\n".join(lines)


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
