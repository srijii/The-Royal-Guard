extends Control

const SAVE_PATH := "user://savegame.json"
const OPTIONS_PATH := "user://options.cfg"

const ACTION_LABELS := {
	"up":     "Move Up",
	"down":   "Move Down",
	"left":   "Move Left",
	"right":  "Move Right",
	"hold_map_zoom":    "Show Map",
	"attack":           "Attack",
	"sprint":           "Sprint",
	"use_health_potion":   "Use Regeneration",
	"use_strength_potion": "Use Strength Potion",
	"use_energy_drink":    "Use Energy Drink",
}

const KEYBIND_SECTIONS := {
	"Movement": ["up", "down", "left", "right"],
	"Combat":   ["hold_map_zoom", "attack", "sprint"],
	"Items":    ["use_health_potion", "use_strength_potion", "use_energy_drink"],
}

@onready var _continue_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ContinueButton
var _settings_popup: AcceptDialog = null


func _ready():
	_ensure_default_bind_actions()
	_apply_royal_theme()
	_build_settings_popup()
	if _continue_button:
		_continue_button.disabled = not FileAccess.file_exists(SAVE_PATH)


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
	_settings_popup.popup_centered_ratio(0.55)


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

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.078, 0.157, 0.94)
	panel_style.border_color = Color(0.78, 0.60, 0.24, 0.85)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	panel_style.shadow_size = 14
	panel_style.shadow_offset = Vector2(0, 4)

	var game_theme := Theme.new()
	game_theme.set_stylebox("panel", "PanelContainer", panel_style)

	var btn_base := StyleBoxFlat.new()
	btn_base.bg_color = Color(0.086, 0.125, 0.267, 1.0)
	btn_base.border_color = Color(0.78, 0.60, 0.24, 0.7)
	btn_base.border_width_left = 1
	btn_base.border_width_top = 1
	btn_base.border_width_right = 1
	btn_base.border_width_bottom = 1
	btn_base.corner_radius_top_left = 5
	btn_base.corner_radius_top_right = 5
	btn_base.corner_radius_bottom_left = 5
	btn_base.corner_radius_bottom_right = 5

	var btn_hover := btn_base.duplicate()
	btn_hover.bg_color = Color(0.118, 0.176, 0.376, 1.0)
	btn_hover.border_color = Color(0.90, 0.72, 0.35, 1.0)
	btn_hover.shadow_color = Color(0.78, 0.60, 0.24, 0.25)
	btn_hover.shadow_size = 5

	var btn_pressed := btn_base.duplicate()
	btn_pressed.bg_color = Color(0.063, 0.090, 0.196, 1.0)
	btn_pressed.border_color = Color(0.60, 0.45, 0.18, 1.0)

	var btn_disabled := btn_base.duplicate()
	btn_disabled.bg_color = Color(0.039, 0.055, 0.118, 1.0)
	btn_disabled.border_color = Color(0.35, 0.28, 0.15, 0.4)

	game_theme.set_stylebox("normal", "Button", btn_base)
	game_theme.set_stylebox("hover", "Button", btn_hover)
	game_theme.set_stylebox("pressed", "Button", btn_pressed)
	game_theme.set_stylebox("disabled", "Button", btn_disabled)

	game_theme.set_constant("minimum_height", "Button", 46)
	game_theme.set_color("font_color", "Button", Color(0.91, 0.86, 0.75, 1.0))
	game_theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.85, 1.0))
	game_theme.set_color("font_pressed_color", "Button", Color(0.85, 0.78, 0.60, 1.0))
	game_theme.set_color("font_disabled_color", "Button", Color(0.45, 0.40, 0.30, 0.6))

	var panel := get_node_or_null("PanelContainer") as PanelContainer
	if panel:
		panel.theme = game_theme

	var title := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Title") as Label
	if title:
		title.add_theme_font_override("font", royal_font)
		title.add_theme_font_size_override("font_size", 44)
		title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50, 1.0))
		title.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.02, 0.95))
		title.add_theme_constant_override("outline_size", 3)

	var subtitle := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Subtitle") as Label
	if subtitle:
		subtitle.text = "♛  THE ROYAL GUARD  ♛"
		subtitle.add_theme_font_override("font", royal_font)
		subtitle.add_theme_font_size_override("font_size", 16)
		subtitle.add_theme_color_override("font_color", Color(0.78, 0.68, 0.52, 1.0))

	for btn_path in [
		"PanelContainer/MarginContainer/VBoxContainer/NewGameButton",
		"PanelContainer/MarginContainer/VBoxContainer/ContinueButton",
		"PanelContainer/MarginContainer/VBoxContainer/SettingsButton",
		"PanelContainer/MarginContainer/VBoxContainer/CreditsButton",
		"PanelContainer/MarginContainer/VBoxContainer/ExitButton"
	]:
		var button := get_node_or_null(btn_path) as Button
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
	])
	return fallback


func _build_settings_popup() -> void:
	_settings_popup = AcceptDialog.new()
	_settings_popup.title = "⚙  Settings"
	_settings_popup.dialog_text = ""
	_settings_popup.exclusive = true
	add_child(_settings_popup)

	var light_gold := Color(0.95, 0.82, 0.50, 1.0)
	var cream := Color(0.91, 0.86, 0.75, 1.0)
	var dark_bg := Color(0.086, 0.125, 0.267, 1.0)

	var popup_theme := Theme.new()
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.055, 0.078, 0.157, 0.97)
	popup_style.border_color = Color(0.78, 0.60, 0.24, 0.7)
	popup_style.border_width_left = 2
	popup_style.border_width_top = 2
	popup_style.border_width_right = 2
	popup_style.border_width_bottom = 2
	popup_style.corner_radius_top_left = 10
	popup_style.corner_radius_top_right = 10
	popup_style.corner_radius_bottom_left = 10
	popup_style.corner_radius_bottom_right = 10
	popup_theme.set_stylebox("panel", "Window", popup_style)
	popup_theme.set_color("title_color", "Window", Color(0.95, 0.82, 0.50, 1.0))

	var popup_btn := StyleBoxFlat.new()
	popup_btn.bg_color = dark_bg
	popup_btn.border_color = Color(0.78, 0.60, 0.24, 0.6)
	popup_btn.border_width_left = 1
	popup_btn.border_width_top = 1
	popup_btn.border_width_right = 1
	popup_btn.border_width_bottom = 1
	popup_btn.corner_radius_top_left = 4
	popup_btn.corner_radius_top_right = 4
	popup_btn.corner_radius_bottom_left = 4
	popup_btn.corner_radius_bottom_right = 4

	var popup_btn_hover := popup_btn.duplicate()
	popup_btn_hover.bg_color = Color(0.118, 0.176, 0.376, 1.0)
	popup_btn_hover.border_color = Color(0.90, 0.72, 0.35, 0.8)

	popup_theme.set_stylebox("normal", "Button", popup_btn)
	popup_theme.set_stylebox("hover", "Button", popup_btn_hover)
	popup_theme.set_color("font_color", "Button", cream)
	popup_theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.85, 1.0))
	popup_theme.set_color("font_color", "Label", cream)
	popup_theme.set_color("font_color", "Window", cream)
	popup_theme.set_constant("minimum_height", "Button", 30)

	_settings_popup.theme = popup_theme

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(540, 420)
	root.add_theme_constant_override("separation", 8)
	root.add_theme_constant_override("h_separation", 0)
	_settings_popup.add_child(root)

	var bottom_margin := Control.new()
	bottom_margin.custom_minimum_size = Vector2(0, 4)
	root.add_child(bottom_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)

	for section_name in KEYBIND_SECTIONS.keys():
		var actions := KEYBIND_SECTIONS[section_name] as Array

		var section_label := Label.new()
		section_label.text = "—  " + section_name + "  —"
		section_label.add_theme_color_override("font_color", light_gold)
		section_label.add_theme_font_size_override("font_size", 14)
		section_label.custom_minimum_size = Vector2(0, 28)
		list.add_child(section_label)

		for action_name in actions:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.custom_minimum_size = Vector2(0, 30)
			list.add_child(row)

			var action_label := Label.new()
			action_label.text = String(ACTION_LABELS.get(action_name, action_name))
			action_label.custom_minimum_size = Vector2(220, 0)
			action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(action_label)

			var bind_label := Label.new()
			bind_label.text = _describe_action_binding(action_name)
			bind_label.custom_minimum_size = Vector2(140, 0)
			bind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(bind_label)

		list.add_child(_make_section_spacer(6))

	var toggle_section := VBoxContainer.new()
	toggle_section.add_theme_constant_override("separation", 6)
	root.add_child(toggle_section)

	var toggle_header := Label.new()
	toggle_header.text = "—  Controls  —"
	toggle_header.add_theme_color_override("font_color", light_gold)
	toggle_header.add_theme_font_size_override("font_size", 14)
	toggle_header.custom_minimum_size = Vector2(0, 28)
	toggle_section.add_child(toggle_header)

	var toggle_row := HBoxContainer.new()
	toggle_row.custom_minimum_size = Vector2(0, 36)
	toggle_section.add_child(toggle_row)

	var screen_label := Label.new()
	screen_label.text = "Enable Screen Controls"
	screen_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(screen_label)

	var check := CheckButton.new()
	check.button_pressed = _is_mobile_controls_enabled()
	check.toggled.connect(_on_mobile_controls_toggled)
	toggle_row.add_child(check)


func _make_section_spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s


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
	for action_name in ["up", "down", "left", "right", "attack", "sprint"]:
		_ensure_action_key(action_name, KEY_SPACE)
	_ensure_action_key("hold_map_zoom", KEY_M)
	_ensure_action_key("use_health_potion", KEY_SPACE)
	_ensure_action_key("use_strength_potion", KEY_J)
	_ensure_action_key("use_energy_drink", KEY_K)


func _ensure_action_key(action_name: String, default_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if InputMap.action_get_events(action_name).is_empty():
		var ev := InputEventKey.new()
		ev.keycode = default_keycode
		InputMap.action_add_event(action_name, ev)


func _is_mobile_controls_enabled() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		return false
	return bool(cfg.get_value("controls", "mobile_controls", false))


func _on_mobile_controls_toggled(_enabled: bool) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		pass
	cfg.set_value("controls", "mobile_controls", _enabled)
	cfg.save(OPTIONS_PATH)
