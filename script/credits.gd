extends Control

var _roles := {
	"Card1": { "role": "Lead Developer" },
	"Card2": { "role": "Game Designer" },
	"Card3": { "role": "UI / Art Designer" },
	"Card4": { "role": "QA / Narrative Designer" },
}


func _ready():
	_apply_royal_theme()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed():
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


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

	game_theme.set_stylebox("normal", "Button", btn_base)
	game_theme.set_stylebox("hover", "Button", btn_hover)
	game_theme.set_stylebox("pressed", "Button", btn_pressed)
	game_theme.set_color("font_color", "Button", Color(0.91, 0.86, 0.75, 1.0))
	game_theme.set_color("font_hover_color", "Button", Color(1.0, 0.95, 0.85, 1.0))

	var panel := get_node_or_null("PanelContainer") as PanelContainer
	if panel:
		panel.theme = game_theme

	var title := get_node_or_null("PanelContainer/MarginContainer/Content/Title") as Label
	if title:
		title.add_theme_font_override("font", royal_font)
		title.add_theme_font_size_override("font_size", 38)
		title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50, 1.0))
		title.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.02, 0.95))
		title.add_theme_constant_override("outline_size", 2)

	var desc := get_node_or_null("PanelContainer/MarginContainer/Content/GameDescription") as Label
	if desc:
		desc.add_theme_font_override("font", royal_font)
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.78, 0.68, 0.52, 1.0))

	var creator_title := get_node_or_null("PanelContainer/MarginContainer/Content/CreatorTitle") as Label
	if creator_title:
		creator_title.add_theme_font_override("font", royal_font)
		creator_title.add_theme_font_size_override("font_size", 18)
		creator_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55, 1.0))

	for card_name in ["Card1", "Card2", "Card3", "Card4"]:
		var base := "PanelContainer/MarginContainer/Content/CreatorCenter/CreatorRow/%s" % card_name

		var card := get_node_or_null(base) as VBoxContainer
		if card:
			var card_style := StyleBoxFlat.new()
			card_style.bg_color = Color(0.086, 0.125, 0.267, 0.4)
			card_style.border_color = Color(0.60, 0.45, 0.18, 0.5)
			card_style.border_width_left = 1
			card_style.border_width_top = 1
			card_style.border_width_right = 1
			card_style.border_width_bottom = 1
			card_style.corner_radius_top_left = 8
			card_style.corner_radius_top_right = 8
			card_style.corner_radius_bottom_left = 8
			card_style.corner_radius_bottom_right = 8
			card.add_theme_stylebox_override("panel", card_style)

		var photo := get_node_or_null(base + "/Photo") as TextureRect
		if photo:
			var photo_style := StyleBoxFlat.new()
			photo_style.border_color = Color(0.78, 0.60, 0.24, 0.7)
			photo_style.border_width_left = 2
			photo_style.border_width_top = 2
			photo_style.border_width_right = 2
			photo_style.border_width_bottom = 2
			photo.add_theme_stylebox_override("panel", photo_style)

		var name_label := get_node_or_null(base + "/Name") as Label
		if name_label:
			name_label.add_theme_font_override("font", royal_font)
			name_label.add_theme_font_size_override("font_size", 14)
			name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65, 1.0))

		var role_data = _roles.get(card_name, {})
		if role_data.has("role"):
			var existing_role := get_node_or_null(base + "/RoleLabel") as Label
			if existing_role == null:
				var role_label := Label.new()
				role_label.name = "RoleLabel"
				role_label.text = role_data.role
				role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				role_label.add_theme_font_size_override("font_size", 11)
				role_label.add_theme_color_override("font_color", Color(0.78, 0.60, 0.24, 1.0))
				var card_node := get_node_or_null(base) as VBoxContainer
				if card_node:
					card_node.add_child(role_label)

	var back_button := get_node_or_null("PanelContainer/MarginContainer/Content/Footer/BackButton") as Button
	if back_button:
		back_button.add_theme_font_override("font", royal_font)
		back_button.add_theme_font_size_override("font_size", 14)

	var footer_label := get_node_or_null("PanelContainer/MarginContainer/Content/Footer/FooterLabel") as Label
	if footer_label:
		footer_label.text = "♛  The Royal Guard  •  3rd Year College Project  •  2026  ♛"
		footer_label.add_theme_font_override("font", royal_font)
		footer_label.add_theme_font_size_override("font_size", 10)
		footer_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.45, 1.0))


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
