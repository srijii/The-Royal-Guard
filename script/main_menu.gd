extends Control

const SAVE_PATH := "user://savegame.json"

@onready var _continue_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ContinueButton

# Called when the node enters the scene tree for the new time.
func _ready():
	_apply_classic_theme()
	if _continue_button:
		_continue_button.disabled = not FileAccess.file_exists(SAVE_PATH)

# Called every frame. 'delta' is the time elapsed since the last frame.
func _process(delta):
	pass

func _on_new_game_pressed():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	# Load and start the game world
	print("Attempting to load world scene...")
	var error = get_tree().change_scene_to_file("res://scene/world.tscn")
	if error != OK:
		printerr("Failed to load world scene. Error code: ", error)
		print("Available error codes: OK=0, FAILED=1, ERR_UNAVAILABLE=2, ERR_UNCONFIGURED=3")
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
	# You can create a settings menu later
	print("Settings - To be implemented")

func _on_credits_pressed():
	# Load the credits scene
	print("Loading credits...")
	var error = get_tree().change_scene_to_file("res://scene/credits.tscn")
	if error != OK:
		printerr("Failed to load credits scene: ", error)
	else:
		print("Credits scene loaded successfully!")

func _on_exit_pressed():
	# Close the game
	get_tree().quit()


func _apply_classic_theme() -> void:
	var handwritten_font := _create_handwritten_font()
	var background := get_node_or_null("Background") as ColorRect
	if background:
		background.color = Color(0.08, 0.06, 0.04, 1.0)

	var panel := get_node_or_null("PanelContainer") as PanelContainer
	if panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.17, 0.12, 0.08, 0.96)
		panel_style.border_color = Color(0.78, 0.66, 0.42, 0.85)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
		panel_style.corner_radius_top_left = 10
		panel_style.corner_radius_top_right = 10
		panel_style.corner_radius_bottom_left = 10
		panel_style.corner_radius_bottom_right = 10
		panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		panel_style.shadow_size = 8

		var theme := Theme.new()
		theme.set_stylebox("panel", "PanelContainer", panel_style)
		theme.set_font("font", "Button", handwritten_font)

		var button_normal := StyleBoxFlat.new()
		button_normal.bg_color = Color(0.26, 0.18, 0.1, 1.0)
		button_normal.border_color = Color(0.82, 0.71, 0.48, 0.9)
		button_normal.border_width_left = 1
		button_normal.border_width_top = 1
		button_normal.border_width_right = 1
		button_normal.border_width_bottom = 1
		button_normal.corner_radius_top_left = 6
		button_normal.corner_radius_top_right = 6
		button_normal.corner_radius_bottom_left = 6
		button_normal.corner_radius_bottom_right = 6

		var button_hover := button_normal.duplicate()
		button_hover.bg_color = Color(0.33, 0.23, 0.13, 1.0)

		var button_pressed := button_normal.duplicate()
		button_pressed.bg_color = Color(0.21, 0.15, 0.09, 1.0)

		theme.set_stylebox("normal", "Button", button_normal)
		theme.set_stylebox("hover", "Button", button_hover)
		theme.set_stylebox("pressed", "Button", button_pressed)
		theme.set_stylebox("disabled", "Button", button_pressed)
		theme.set_color("font_color", "Button", Color(0.95, 0.9, 0.78, 1.0))
		theme.set_color("font_focus_color", "Button", Color(0.99, 0.95, 0.86, 1.0))
		theme.set_color("font_hover_color", "Button", Color(0.99, 0.95, 0.86, 1.0))
		theme.set_color("font_pressed_color", "Button", Color(0.95, 0.9, 0.78, 1.0))
		theme.set_color("font_disabled_color", "Button", Color(0.68, 0.61, 0.48, 1.0))
		panel.theme = theme

	var title := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Title") as Label
	if title:
		title.text = "ROYAL GUARD"
		title.add_theme_font_override("font", handwritten_font)
		title.add_theme_font_size_override("font_size", 46)
		title.add_theme_color_override("font_color", Color(0.97, 0.82, 0.52, 1.0))
		title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.95))
		title.add_theme_constant_override("outline_size", 2)

	var subtitle := get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/Subtitle") as Label
	if subtitle:
		subtitle.text = "A classic palace tale"
		subtitle.add_theme_font_override("font", handwritten_font)
		subtitle.add_theme_font_size_override("font_size", 18)
		subtitle.add_theme_color_override("font_color", Color(0.9, 0.84, 0.72, 1.0))

	for path in [
		"PanelContainer/MarginContainer/VBoxContainer/NewGameButton",
		"PanelContainer/MarginContainer/VBoxContainer/ContinueButton",
		"PanelContainer/MarginContainer/VBoxContainer/SettingsButton",
		"PanelContainer/MarginContainer/VBoxContainer/CreditsButton",
		"PanelContainer/MarginContainer/VBoxContainer/ExitButton"
	]:
		var button := get_node_or_null(path) as Button
		if button:
			button.add_theme_font_override("font", handwritten_font)


func _create_handwritten_font() -> SystemFont:
	var game_font := load("res://fonts/Retro Gaming.ttf") as Font
	if game_font:
		return game_font

	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray([
		"Retro Gaming",
		"Segoe Script",
		"Bradley Hand ITC",
		"Lucida Handwriting",
		"Comic Sans MS"
	])
	return fallback
