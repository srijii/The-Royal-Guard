extends Control

const SAVE_PATH := "user://savegame.json"
const KEYBINDS_PATH := "user://keybinds.cfg"
const OPTIONS_PATH := "user://options.cfg"

const ACTION_LABELS := {
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

@onready var _continue_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ContinueButton
var _settings_popup: AcceptDialog = null
var _keybind_buttons: Dictionary = {}
var _rebind_target_action := ""
var _rebind_info_label: Label = null
var _mobile_controls_check: CheckBox = null


func _ready():
	_ensure_default_bind_actions()
	_load_saved_keybinds()
	_apply_royal_theme()
	_build_settings_popup()
	if _continue_button:
		_continue_button.disabled = not FileAccess.file_exists(SAVE_PATH)


func _process(_delta):
	pass


func _on_new_game_pressed():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	print("Attempting to load world scene...")
	var error = get_tree().change_scene_to_file("res://scene/world.tscn")
	if error != OK:
		printerr("Failed to load world scene. Error code: ", error)
	else:
		print("World scene loaded successfully!")


func _on_continue_pressed():
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save found to continue.")
		return
	print("Loading saved game...")
	var error = get_tree().change_scene_to_file("res://scene/world.tscn")
	if error != OK:
		printerr("Failed to load world scene for continue. Error code: ", error)


func _on_settings_pressed():
	if _settings_popup == null:
		return
	_rebind_target_action = ""
	_rebind_info_label.text = "Click Rebind, then press any key."
	_refresh_keybind_button_labels()
	_settings_popup.popup_centered_ratio(0.6)


func _on_credits_pressed():
	print("Loading credits...")
	var error = get_tree().change_scene_to_file("res://scene/credits.tscn")
	if error != OK:
		printerr("Failed to load credits scene: ", error)
	else:
		print("Credits scene loaded successfully!")


func _on_exit_pressed():
	get_tree().quit()


func _apply_royal_theme() -> void:
	var royal_font := _create_royal_font()

	var bg := get_node_or_null("Background") as ColorRect
	if bg:
		bg.color = Color(0.06, 0.03, 0.10, 1.0)

	var panel := get_node_or_null("PanelContainer") as PanelContainer
	if panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.10, 0.06, 0.04, 0.92)
		panel_style.border_color = Color(0.72, 0.55, 0.25, 0.9)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
		panel_style.corner_radius_top_left = 14
		panel_style.corner_radius_top_right = 14
		panel_style.corner_radius_bottom_left = 14
		panel_style.corner_radius_bottom_right = 14
		panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		panel_style.shadow_size = 12
		panel_style.shadow_offset = Vector2(0, 4)
		panel_style.anti_aliasing = true

		var inner_glow := StyleBoxFlat.new()
		inner_glow.bg_color = Color(0.12, 0.07, 0.05, 0.0)
		inner_glow.border_color = Color(0.9, 0.75, 0.4, 0.15)
		inner_glow.border_width_left = 1
		inner_glow.border_width_top = 1
		inner_glow.border_width_right = 1
		inner_glow.border_width_bottom = 1
		inner_glow.corner_radius_top_left = 12
		inner_glow.corner_radius_top_right = 12
		inner_glow.corner_radius_bottom_left = 12
		inner_glow.corner_radius_bottom_right = 12

		var game_theme := Theme.new()
		game_theme.set_stylebox("panel", "PanelContainer", panel_style)
		game_theme.set_stylebox("panel", "MarginContainer", inner_glow)

		var button_normal := StyleBoxFlat.new()
		button_normal.bg_color = Color(0.22, 0.14, 0.08, 1.0)
		button_normal.border_color = Color(0.72, 0.55, 0.25, 0.8)
		button_normal.border_width_left = 1
		button_normal.border_width_top = 1
		button_normal.border_width_right = 1
		button_normal.border_width_bottom = 1
		button_normal.corner_radius_top_left = 6
		button_normal.corner_radius_top_right = 6
		button_normal.corner_radius_bottom_left = 6
		button_normal.corner_radius_bottom_right = 6

		var button_hover := button_normal.duplicate()
		button_hover.bg_color = Color(0.32, 0.20, 0.10, 1.0)
		button_hover.border_color = Color(0.90, 0.72, 0.35, 1.0)
		button_hover.shadow_color = Color(0.72, 0.55, 0.25, 0.3)
		button_hover.shadow_size = 4

		var button_pressed := button_normal.duplicate()
		button_pressed.bg_color = Color(0.16, 0.10, 0.06, 1.0)
		button_pressed.border_color = Color(0.60, 0.45, 0.20, 1.0)

		var button_disabled := button_normal.duplicate()
		button_disabled.bg_color = Color(0.12, 0.08, 0.05, 1.0)
		button_disabled.border_color = Color(0.35, 0.28, 0.15, 0.5)

		game_theme.set_stylebox("normal", "Button", button_normal)
		game_theme.set_stylebox("hover", "Button", button_hover)
		game_theme.set_stylebox("pressed", "Button", button_pressed)
		game_theme.set_stylebox("disabled", "Button", button_disabled)

		game_theme.set_constant("minimum_height", "Button", 46)

		game_theme.set_color("font_color", "Button", Color(0.95, 0.90, 0.78, 1.0))
		game_theme.set_color("font_focus_color", "Button", Color(1.0, 0.95, 0.85, 1.0))
		game_theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.85, 1.0))
		game_theme.set_color("font_pressed_color", "Button", Color(0.90, 0.82, 0.65, 1.0))
		game_theme.set_color("font_disabled_color", "Button", Color(0.50, 0.45, 0.35, 0.7))
		panel.theme = game_theme

	var crown_label := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/CrownLabel") as Label
	if crown_label:
		crown_label.add_theme_font_size_override("font_size", 36)
		crown_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.25, 1.0))
		crown_label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 0.8))
		crown_label.add_theme_constant_override("outline_size", 1)

	var deco_top_line := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/DecoTopLine") as ColorRect
	if deco_top_line:
		deco_top_line.color = Color(0.72, 0.55, 0.25, 0.5)

	var deco_bottom_line := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/DecoBottomLine") as ColorRect
	if deco_bottom_line:
		deco_bottom_line.color = Color(0.72, 0.55, 0.25, 0.5)

	var title := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Title") as Label
	if title:
		title.add_theme_font_override("font", royal_font)
		title.add_theme_font_size_override("font_size", 44)
		title.add_theme_color_override("font_color", Color(0.97, 0.82, 0.52, 1.0))
		title.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.95))
		title.add_theme_constant_override("outline_size", 3)

	var subtitle := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Subtitle") as Label
	if subtitle:
		subtitle.text = "⚔  Defend the Crown  ⚔"
		subtitle.add_theme_font_override("font", royal_font)
		subtitle.add_theme_font_size_override("font_size", 16)
		subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.60, 1.0))

	for path in [
		"PanelContainer/MarginContainer/VBoxContainer/NewGameButton",
		"PanelContainer/MarginContainer/VBoxContainer/ContinueButton",
		"PanelContainer/MarginContainer/VBoxContainer/SettingsButton",
		"PanelContainer/MarginContainer/VBoxContainer/CreditsButton",
		"PanelContainer/MarginContainer/VBoxContainer/ExitButton"
	]:
		var button := get_node_or_null(path) as Button
		if button:
			button.add_theme_font_override("font", royal_font)
			button.add_theme_font_size_override("font_size", 16)


func _create_royal_font() -> Font:
	var game_font := load("res://fonts/Retro Gaming.ttf") as Font
	if game_font:
		return game_font

	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray([
		"Retro Gaming",
		"Noto Serif",
		"Liberation Serif",
		"FreeSerif",
		"Segoe Script",
		"Bradley Hand ITC",
	])
	return fallback


func _build_settings_popup() -> void:
	_settings_popup = AcceptDialog.new()
	_settings_popup.title = "Settings"
	_settings_popup.dialog_text = ""
	_settings_popup.exclusive = true
	add_child(_settings_popup)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 420)
	root.add_theme_constant_override("separation", 8)
	_settings_popup.add_child(root)

	var subtitle := Label.new()
	subtitle.text = "Controls"
	subtitle.add_theme_font_size_override("font_size", 18)
	root.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 300)
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for action_name in ACTION_LABELS.keys():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)

		var action_label := Label.new()
		action_label.text = String(ACTION_LABELS[action_name])
		action_label.custom_minimum_size = Vector2(230, 0)
		row.add_child(action_label)

		var bind_button := Button.new()
		bind_button.text = _describe_action_binding(action_name)
		bind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind_button.pressed.connect(_start_rebind.bind(action_name))
		row.add_child(bind_button)
		_keybind_buttons[action_name] = bind_button

	_mobile_controls_check = CheckBox.new()
	_mobile_controls_check.text = "Enable mobile joystick + touch buttons"
	_mobile_controls_check.button_pressed = _load_mobile_controls_option()
	_mobile_controls_check.toggled.connect(_on_mobile_controls_toggled)
	root.add_child(_mobile_controls_check)

	_rebind_info_label = Label.new()
	_rebind_info_label.text = "Click Rebind, then press any key."
	_rebind_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_rebind_info_label)


func _start_rebind(action_name: String) -> void:
	_rebind_target_action = action_name
	_rebind_info_label.text = "Press a key for %s" % ACTION_LABELS.get(action_name, action_name)


func _unhandled_input(event: InputEvent) -> void:
	if _rebind_target_action == "":
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		_assign_action_event(_rebind_target_action, key_event)
		get_viewport().set_input_as_handled()


func _assign_action_event(action_name: String, event: InputEventKey) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	InputMap.action_erase_events(action_name)
	var assigned := InputEventKey.new()
	assigned.keycode = event.keycode
	assigned.shift_pressed = event.shift_pressed
	assigned.ctrl_pressed = event.ctrl_pressed
	assigned.alt_pressed = event.alt_pressed
	assigned.meta_pressed = event.meta_pressed
	InputMap.action_add_event(action_name, assigned)

	_save_keybinds()
	_rebind_target_action = ""
	_refresh_keybind_button_labels()
	_rebind_info_label.text = "Saved keybind."


func _refresh_keybind_button_labels() -> void:
	for action_name in _keybind_buttons.keys():
		var button := _keybind_buttons[action_name] as Button
		if button:
			button.text = _describe_action_binding(String(action_name))


func _describe_action_binding(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "Unbound"

	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return "Unbound"

	var first := events[0]
	if first is InputEventKey:
		return (first as InputEventKey).as_text_keycode()
	return first.as_text()


func _ensure_default_bind_actions() -> void:
	_ensure_action_key("attack", KEY_CTRL)
	_ensure_action_key("sprint", KEY_SHIFT)
	_set_action_key("hold_map_zoom", KEY_M)
	_set_action_key("use_health_potion", KEY_SPACE)
	_set_action_key("use_strength_potion", KEY_J)
	_set_action_key("use_energy_drink", KEY_K)


func _ensure_action_key(action_name: String, default_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if InputMap.action_get_events(action_name).is_empty():
		var ev := InputEventKey.new()
		ev.keycode = default_keycode
		InputMap.action_add_event(action_name, ev)


func _set_action_key(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	InputMap.action_erase_events(action_name)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action_name, ev)


func _save_keybinds() -> void:
	var cfg := ConfigFile.new()
	for action_name in ACTION_LABELS.keys():
		cfg.set_value("bindings", action_name, InputMap.action_get_events(action_name))
	cfg.save(KEYBINDS_PATH)


func _load_saved_keybinds() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(KEYBINDS_PATH) != OK:
		return

	for action_name in ACTION_LABELS.keys():
		var events = cfg.get_value("bindings", action_name, null)
		if events == null:
			continue
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)
		for ev in events:
			if ev is InputEvent:
				InputMap.action_add_event(action_name, ev)


func _on_mobile_controls_toggled(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		pass
	cfg.set_value("controls", "mobile_controls", enabled)
	cfg.save(OPTIONS_PATH)


func _load_mobile_controls_option() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		return false
	return bool(cfg.get_value("controls", "mobile_controls", false))
