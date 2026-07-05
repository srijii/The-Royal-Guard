extends CanvasLayer

# Death screen UI controller - shows when player dies and handles respawn

var _death_panel: PanelContainer = null
var _respawn_button: Button = null
var _is_showing := false
var _death_connections_done := false


func _ready() -> void:
	# Hide initially
	visible = false
	_create_death_ui()
	_connect_player_death_signals()


func _create_death_ui() -> void:
	# Create main panel
	_death_panel = PanelContainer.new()
	_death_panel.anchor_left = 0.0
	_death_panel.anchor_top = 0.0
	_death_panel.anchor_right = 1.0
	_death_panel.anchor_bottom = 1.0
	add_child(_death_panel)
	
	# Set background color (dark cinematic fade)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.0, 0.0, 0.0)
	_death_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Create VBox container for content
	var vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -150
	vbox.offset_top = -100
	vbox.custom_minimum_size = Vector2(300, 200)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	vbox.modulate.a = 0.0
	_death_panel.add_child(vbox)
	
	# "You Died" title
	var title_label = Label.new()
	title_label.text = "YOU DIED"
	title_label.add_theme_font_size_override("font_size", 58)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.12, 0.12, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title_label.add_theme_constant_override("shadow_offset_x", 2)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	# Respawn message
	var message_label = Label.new()
	message_label.text = "The battle is lost..."
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.55, 0.8))
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message_label)
	
	# Respawn button
	_respawn_button = Button.new()
	_respawn_button.text = "Try Again"
	_respawn_button.custom_minimum_size = Vector2(220, 52)
	_respawn_button.add_theme_font_size_override("font_size", 22)
	_respawn_button.pressed.connect(_on_respawn_pressed)
	vbox.add_child(_respawn_button)


func _on_player_died() -> void:
	if _is_showing:
		return
	
	_is_showing = true
	_freeze_all_characters()

	# Show death screen with cinematic fade
	visible = true
	_death_panel.visible = true

	# Animate dark red tint fade in
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.0, 0.0, 0.0)
	_death_panel.add_theme_stylebox_override("panel", panel_style)

	var content = _death_panel.get_node_or_null("Content")
	if content:
		content.modulate.a = 0.0

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel_style, "bg_color", Color(0.05, 0.0, 0.0, 0.82), 1.2).set_ease(Tween.EASE_OUT)
	if content:
		tween.tween_property(content, "modulate:a", 1.0, 0.8).set_delay(0.5).set_ease(Tween.EASE_OUT)
	await tween.finished

	if _respawn_button != null:
		_respawn_button.grab_focus()


func _on_respawn_pressed() -> void:
	# Load outerworld as the checkpoint
	get_tree().change_scene_to_file("res://scene/outerworld.tscn")


func _connect_player_death_signals() -> void:
	if _death_connections_done:
		return
	_death_connections_done = true

	var players := get_tree().get_nodes_in_group("player")
	for player in players:
		if player.has_signal("died") and not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)


func _freeze_all_characters() -> void:
	var current := get_tree().current_scene
	if current == null:
		return

	var bodies := current.find_children("*", "CharacterBody2D", true, false)
	for node in bodies:
		if not (node is CharacterBody2D):
			continue

		var body := node as CharacterBody2D
		body.velocity = Vector2.ZERO

		if body.has_method("set_controls_enabled"):
			body.call("set_controls_enabled", false)

		body.process_mode = Node.PROCESS_MODE_DISABLED
