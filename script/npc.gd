extends CharacterBody2D

signal night_started(queen_position: Vector2)
signal exploration_started

@export var dialogue_world_offset := Vector2(0.0, -40.0)
@export var teleport_offset := Vector2(140.0, -100.0)
@export var teleport_pause_seconds := 0.32
@export var typing_characters_per_second := 95.0
@export var caption_fade_seconds := 0.18
@export var wander_speed := 40.0
@export var wander_arrive_distance := 14.0
@export var wander_wait_range := Vector2(0.7, 1.8)
@export var view_distance := 220.0
@export var view_angle_degrees := 80.0
@export var ahead_check_distance := 44.0
@export var detour_scan_distance := 180.0
@export var detour_scan_rays := 9
@export var detour_scan_angle_degrees := 120.0
@export var player_personal_space_radius := 26.0
@export var step_away_distance := 42.0
@export var view_attention_pause_seconds := 0.26
@export var view_attention_cooldown_seconds := 1.2
@export var wander_stuck_seconds := 0.6
@export var wander_progress_epsilon := 4.0
@export var view_debug_visible := false

var _sprite: AnimatedSprite2D = null
var _player_ref: Node2D = null
var _canvas_modulate: CanvasModulate = null

var _dialogue_layer: CanvasLayer = null
var _dialogue_panel: PanelContainer = null
var _dialogue_label: RichTextLabel = null
var _continue_row: HBoxContainer = null
var _caption_fade_tween: Tween = null

var _night_started := false
var _waiting_for_advance := false
var _advance_requested := false
var _return_sequence_started := false
var _exploration_started := false
var _story_sequence_started := false
var _story_completed := false
var _suppress_story_from_save := false
var _skip_tutorial_requested := false
var _is_typing := false
var _skip_typing_requested := false
var _wander_enabled := false
var _wander_area := Rect2(Vector2(-600, -360), Vector2(1200, 900))
var _wander_polygon := PackedVector2Array()
var _wander_checkpoints: Array[Vector2] = []
var _wander_target := Vector2.ZERO
var _wander_primary_target := Vector2.ZERO
var _wander_wait_time_left := 0.0
var _wander_has_target := false
var _wander_has_primary_target := false
var _last_move_dir := Vector2.DOWN
var _attention_cooldown_left := 0.0
var _wander_stuck_time := 0.0
var _last_progress_sample := Vector2.ZERO
var _has_progress_sample := false
var _last_checkpoint_index := -1


func _ready() -> void:
	_sprite = get_node_or_null("AnimatedSprite2D2") as AnimatedSprite2D
	_player_ref = get_parent().get_node_or_null("player") as Node2D
	_canvas_modulate = get_parent().get_node_or_null("CanvasModulate") as CanvasModulate

	if has_node("Camera2D"):
		$Camera2D.enabled = false
	if has_node("PointLight2D"):
		$PointLight2D.visible = false

	if _canvas_modulate:
		_canvas_modulate.visible = false

	_create_dialogue_ui()
	set_process_unhandled_input(true)
	if _sprite:
		_sprite.play("idle-s")
	if _player_ref and _player_ref.has_method("set_controls_enabled"):
		_player_ref.call("set_controls_enabled", false)

	call_deferred("_begin_story_if_needed")


func _begin_story_if_needed() -> void:
	if _suppress_story_from_save or _story_completed or _story_sequence_started:
		if _player_ref and _player_ref.has_method("set_controls_enabled"):
			_player_ref.call("set_controls_enabled", true)
		return
	_run_story_sequence()


func _physics_process(delta: float) -> void:
	if _wander_enabled and not _return_sequence_started and not _night_started:
		_process_wander(delta)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		_set_princess_animation(Vector2.ZERO)

	_update_dialogue_position()
	if view_debug_visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X and _story_sequence_started and not _story_completed and not _exploration_started:
			_skip_tutorial_requested = true
			_skip_typing_requested = true
			_advance_requested = true
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if _is_typing:
				_skip_typing_requested = true
				get_viewport().set_input_as_handled()
				return
			if _waiting_for_advance:
				_advance_requested = true
				get_viewport().set_input_as_handled()


func _run_story_sequence() -> void:
	if _story_sequence_started or _suppress_story_from_save:
		return
	_story_sequence_started = true

	await _say_and_wait("Princess", "Good morning. You must be the new royal guard.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "From today, your duty is to protect me and the royal ring at all costs.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "This ring is ancient. It holds many magical powers created by the royal mages long ago.")
	if _abort_story_if_skipped():
		return

	await _say_timed("Player", "What kind of powers?", 1.7)
	if _abort_story_if_skipped():
		return
	await _say_timed("Princess", "I'll show you one of them.", 1.5)
	if _abort_story_if_skipped():
		return
	await _teleport_demo()
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "And this is only one of its many powers.")
	if _abort_story_if_skipped():
		return

	await _say_and_wait("Princess", "But tonight, during the moon eclipse, the ring will lose all its powers for a short time.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "When that happens, skeleton thieves will appear and try to steal the ring.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "You must protect me until the eclipse ends.")
	if _abort_story_if_skipped():
		return

	await _say_and_wait("Princess", "The eclipse will happen at midnight. We still have some time.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "You should explore the palace and learn the surroundings.")
	if _abort_story_if_skipped():
		return
	await _say_and_wait("Princess", "And bring me a Torch from the storage room.")
	if _abort_story_if_skipped():
		return
	await _say_timed("System", "Quest: Find the Torch", 2.0)
	if _abort_story_if_skipped():
		return
	await _say_timed("Princess", "Return to me before midnight.", 1.7)
	if _abort_story_if_skipped():
		return

	_enter_exploration_phase()


func _abort_story_if_skipped() -> bool:
	if not _skip_tutorial_requested:
		return false
	_enter_exploration_phase()
	return true


func _enter_exploration_phase() -> void:
	_exploration_started = true
	_story_completed = true
	_wander_enabled = true
	_wander_has_target = false
	emit_signal("exploration_started")
	if _player_ref and _player_ref.has_method("set_controls_enabled"):
		_player_ref.call("set_controls_enabled", true)
	_clear_dialogue()


func _teleport_demo() -> void:
	if _skip_tutorial_requested:
		return

	var origin := global_position

	await _say_timed("Princess", "As you can see...", 1.1)
	if _skip_tutorial_requested:
		return
	await _run_fast_teleport_burst(origin)
	if _skip_tutorial_requested:
		return

	await _say_timed("Princess", "I can teleport using the ring.", 1.4)


func _run_fast_teleport_burst(origin: Vector2) -> void:
	# 1-second burst: 3 different directions, then return to origin.
	var burst_total_seconds := 1.0
	var hop_blink_seconds := 0.05

	var targets: Array[Vector2] = [
		origin + teleport_offset,
		origin + Vector2(-teleport_offset.x, -teleport_offset.y * 0.25),
		origin + Vector2(teleport_offset.x * 0.25, absf(teleport_offset.x) * 0.85),
		origin
	]

	var hop_count := targets.size()
	var hop_hold_seconds := maxf(0.02, (burst_total_seconds - (hop_blink_seconds * float(hop_count))) / float(hop_count))

	for target in targets:
		if _skip_tutorial_requested:
			break
		if _sprite:
			_sprite.visible = false
		await get_tree().create_timer(hop_blink_seconds).timeout

		global_position = target
		if _sprite:
			_sprite.visible = true
		await get_tree().create_timer(hop_hold_seconds).timeout

	if _sprite:
		_sprite.play("idle-s")


func _start_night() -> void:
	if _night_started:
		return
	_night_started = true

	emit_signal("night_started", global_position)


func _create_dialogue_ui() -> void:
	_dialogue_layer = CanvasLayer.new()
	_dialogue_layer.layer = 90
	add_child(_dialogue_layer)

	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.custom_minimum_size = Vector2(980, 136)
	_dialogue_panel.visible = false
	_dialogue_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_dialogue_layer.add_child(_dialogue_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.08, 0.05, 0.9)
	panel_style.border_color = Color(0.78, 0.66, 0.42, 0.5)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	panel_style.shadow_size = 8
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12

	var panel_theme := Theme.new()
	panel_theme.set_stylebox("panel", "PanelContainer", panel_style)
	_dialogue_panel.theme = panel_theme
	var handwritten_font := _create_handwritten_font()

	var content := VBoxContainer.new()
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 18
	content.offset_top = 10
	content.offset_right = -18
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 4)
	_dialogue_panel.add_child(content)

	_dialogue_label = RichTextLabel.new()
	_dialogue_label.bbcode_enabled = true
	_dialogue_label.fit_content = true
	_dialogue_label.scroll_active = false
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_label.add_theme_font_override("normal_font", handwritten_font)
	_dialogue_label.add_theme_font_override("bold_font", handwritten_font)
	_dialogue_label.add_theme_font_size_override("normal_font_size", 22)
	_dialogue_label.add_theme_color_override("default_color", Color(0.95, 0.91, 0.82, 1.0))
	_dialogue_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_dialogue_label.add_theme_constant_override("outline_size", 3)
	content.add_child(_dialogue_label)

	_continue_row = HBoxContainer.new()
	_continue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_continue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_row.add_theme_constant_override("separation", 8)
	_continue_row.visible = false
	content.add_child(_continue_row)

	var press_label := Label.new()
	press_label.text = "Press"
	press_label.add_theme_font_override("font", handwritten_font)
	press_label.add_theme_font_size_override("font_size", 13)
	press_label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 0.95))
	press_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	press_label.add_theme_constant_override("outline_size", 2)
	_continue_row.add_child(press_label)
	_continue_row.add_child(_create_key_badge("Enter", handwritten_font))

	var or_label := Label.new()
	or_label.text = "or"
	or_label.add_theme_font_override("font", handwritten_font)
	or_label.add_theme_font_size_override("font_size", 13)
	or_label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 0.95))
	or_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	or_label.add_theme_constant_override("outline_size", 2)
	_continue_row.add_child(or_label)
	_continue_row.add_child(_create_key_badge("Space", handwritten_font))

	var continue_label := Label.new()
	continue_label.text = "to continue"
	continue_label.add_theme_font_override("font", handwritten_font)
	continue_label.add_theme_font_size_override("font_size", 13)
	continue_label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 0.95))
	continue_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	continue_label.add_theme_constant_override("outline_size", 2)
	_continue_row.add_child(continue_label)

	_update_dialogue_position()


func _create_key_badge(text: String, handwritten_font: Font) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(74, 26)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.15, 0.09, 0.96)
	style.border_color = Color(0.88, 0.78, 0.58, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5

	var theme := Theme.new()
	theme.set_stylebox("panel", "PanelContainer", style)
	badge.theme = theme

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.add_theme_font_override("font", handwritten_font)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 1)
	badge.add_child(label)

	return badge


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


func _update_dialogue_position() -> void:
	if _dialogue_panel == null:
		return

	var viewport_size := get_viewport_rect().size
	var panel_size := Vector2(minf(980.0, viewport_size.x - 40.0), 136.0)
	var bottom_margin := 20.0
	_dialogue_panel.size = panel_size
	_dialogue_panel.position = Vector2(
		(viewport_size.x - panel_size.x) * 0.5,
		viewport_size.y - panel_size.y - bottom_margin
	)


func _say_timed(speaker: String, text: String, seconds: float) -> void:
	if _skip_tutorial_requested:
		return
	_set_caption(speaker, text)
	if _continue_row:
		_continue_row.visible = false
	await _type_current_caption()
	if _skip_tutorial_requested:
		return
	var time_left := seconds
	while time_left > 0.0 and not _skip_tutorial_requested:
		var step := minf(0.08, time_left)
		await get_tree().create_timer(step).timeout
		time_left -= step


func _say_and_wait(speaker: String, text: String) -> void:
	if _skip_tutorial_requested:
		return
	_set_caption(speaker, text)
	await _type_current_caption()
	if _skip_tutorial_requested:
		return
	if _continue_row:
		_continue_row.visible = true
	await _wait_for_advance()


func _set_caption(speaker: String, text: String) -> void:
	if _dialogue_label == null:
		return

	_show_caption_panel()

	var resolved_speaker := speaker.strip_edges()
	if resolved_speaker == "":
		_dialogue_label.text = "[center]%s[/center]" % text
		_dialogue_label.visible_characters = 0
		return

	var speaker_hex := _to_hex(_get_speaker_color(resolved_speaker))
	var bb := "[center][color=%s][b]%s:[/b][/color] %s[/center]" % [speaker_hex, resolved_speaker, text]
	_dialogue_label.text = bb
	_dialogue_label.visible_characters = 0


func _show_caption_panel() -> void:
	if _dialogue_panel == null:
		return

	if _caption_fade_tween:
		_caption_fade_tween.kill()

	_dialogue_panel.visible = true
	_caption_fade_tween = create_tween()
	_caption_fade_tween.tween_property(_dialogue_panel, "modulate:a", 1.0, caption_fade_seconds)


func _hide_caption_panel() -> void:
	if _dialogue_panel == null:
		return

	if _caption_fade_tween:
		_caption_fade_tween.kill()

	_caption_fade_tween = create_tween()
	_caption_fade_tween.tween_property(_dialogue_panel, "modulate:a", 0.0, caption_fade_seconds)
	_caption_fade_tween.finished.connect(func() -> void:
		if _dialogue_panel:
			_dialogue_panel.visible = false
	)


func _get_speaker_color(speaker: String) -> Color:
	match speaker:
		"Princess":
			return Color(0.96, 0.79, 0.49, 1.0)
		"Player":
			return Color(0.86, 0.92, 0.98, 1.0)
		"System":
			return Color(0.83, 0.9, 0.79, 1.0)
		_:
			return Color(0.95, 0.91, 0.82, 1.0)


func _to_hex(c: Color) -> String:
	return c.to_html(false)


func _type_current_caption() -> void:
	if _dialogue_label == null:
		return

	var total_chars := _dialogue_label.get_total_character_count()
	if total_chars <= 0:
		_dialogue_label.visible_characters = -1
		return

	_is_typing = true
	_skip_typing_requested = false
	_dialogue_label.visible_characters = 0

	var cps := maxf(typing_characters_per_second, 1.0)
	var step_delay := 1.0 / cps

	while _dialogue_label.visible_characters < total_chars:
		if _skip_typing_requested or _skip_tutorial_requested:
			break
		_dialogue_label.visible_characters += 1
		await get_tree().create_timer(step_delay).timeout

	_dialogue_label.visible_characters = -1
	_is_typing = false
	_skip_typing_requested = false


func _wait_for_advance() -> void:
	_waiting_for_advance = true
	_advance_requested = false
	while not _advance_requested and not _skip_tutorial_requested:
		await get_tree().process_frame
	_waiting_for_advance = false
	_advance_requested = false


func _clear_dialogue() -> void:
	if _dialogue_label:
		_dialogue_label.text = ""
		_dialogue_label.visible_characters = -1
	if _continue_row:
		_continue_row.visible = false
	_hide_caption_panel()


func start_return_with_sword_sequence() -> void:
	start_return_with_torch_sequence()


func start_return_with_torch_sequence() -> void:
	if _return_sequence_started:
		return
	_return_sequence_started = true
	_run_return_with_torch_sequence()


func _run_return_with_torch_sequence() -> void:
	_wander_enabled = false
	if _player_ref and _player_ref.has_method("set_controls_enabled"):
		_player_ref.call("set_controls_enabled", false)

	await _say_and_wait("Princess", "Good, you made it back.")
	await _say_and_wait("Princess", "Now, see the second power of the ring.")
	await _say_timed("System", "The princess makes the torch float beside you.", 1.6)
	if _player_ref and _player_ref.has_method("set_lamp_control_unlocked"):
		_player_ref.call("set_lamp_control_unlocked", true)
	if _player_ref and _player_ref.has_node("PointLight2D"):
		var torch_light := _player_ref.get_node("PointLight2D") as PointLight2D
		if torch_light:
			torch_light.visible = false
	await _say_and_wait("Princess", "From now on, you can summon and return the torch using the L button.")
	await _say_timed("System", "Press L to call the torch.", 1.8)
	await _say_and_wait("Princess", "It's almost midnight. Stay close.")
	await _say_timed("System", "The moon eclipse has begun...", 1.8)
	await _darken_to_night(2.0)
	await _say_timed("Princess", "The ring has lost its power... Be ready.", 1.9)
	_start_night()

	if _player_ref and _player_ref.has_method("set_controls_enabled"):
		_player_ref.call("set_controls_enabled", true)
	_clear_dialogue()


func _darken_to_night(duration: float) -> void:
	if _canvas_modulate == null:
		return

	var target_color := _canvas_modulate.color
	_canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	_canvas_modulate.visible = true

	var tween := create_tween()
	tween.tween_property(_canvas_modulate, "color", target_color, duration)
	await tween.finished


func _process_wander(delta: float) -> void:
	if _attention_cooldown_left > 0.0:
		_attention_cooldown_left = maxf(0.0, _attention_cooldown_left - delta)

	if _step_away_from_player(delta):
		return

	if _wander_wait_time_left > 0.0:
		_wander_wait_time_left = maxf(0.0, _wander_wait_time_left - delta)
		velocity = Vector2.ZERO
		move_and_slide()
		_set_princess_animation(Vector2.ZERO)
		return

	if _player_ref and _is_point_in_view(_player_ref.global_position) and _attention_cooldown_left <= 0.0:
		# If player is seen in front view, stay attentive for a brief moment.
		_wander_wait_time_left = maxf(_wander_wait_time_left, view_attention_pause_seconds)
		_attention_cooldown_left = view_attention_cooldown_seconds
		velocity = Vector2.ZERO
		move_and_slide()
		_set_princess_animation(Vector2.ZERO)
		return

	if not _wander_has_target:
		_pick_new_wander_target()

	if _handle_stuck_repath(delta):
		return

	var to_target := _wander_target - global_position
	if to_target.length() <= wander_arrive_distance:
		if _wander_has_primary_target and global_position.distance_to(_wander_primary_target) > wander_arrive_distance:
			# Continue toward the original destination after a temporary detour.
			_wander_target = _wander_primary_target
			_wander_has_target = true
		else:
			_wander_has_target = false
			_wander_has_primary_target = false
			_wander_wait_time_left = randf_range(wander_wait_range.x, wander_wait_range.y)
			velocity = Vector2.ZERO
			move_and_slide()
			_set_princess_animation(Vector2.ZERO)
			return

	var dir := to_target.normalized()
	if _is_obstacle_ahead(dir):
		if not _pick_detour_target(dir, _wander_primary_target):
			_pick_new_wander_target()
		velocity = Vector2.ZERO
		move_and_slide()
		_set_princess_animation(Vector2.ZERO)
		return

	_last_move_dir = dir
	velocity = dir * wander_speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		if not _pick_detour_target(dir, _wander_primary_target):
			_pick_new_wander_target()
		velocity = Vector2.ZERO
		_set_princess_animation(Vector2.ZERO)
		return

	_set_princess_animation(dir)


func _step_away_from_player(delta: float) -> bool:
	if _player_ref == null:
		return false

	var to_player := _player_ref.global_position - global_position
	var dist := to_player.length()
	if dist > player_personal_space_radius:
		return false

	var away_dir := Vector2.ZERO
	if dist <= 0.001:
		away_dir = -_last_move_dir
		if away_dir.length() <= 0.001:
			away_dir = Vector2.UP
	else:
		away_dir = (-to_player / dist)

	away_dir = away_dir.normalized()
	if away_dir.length() <= 0.001:
		away_dir = Vector2.UP

	# Pick a nearby valid point away from the player to avoid body-pushing drag.
	var target := global_position + away_dir * step_away_distance
	if _is_point_in_wander_space(target):
		_wander_target = target
		_wander_primary_target = target
		_wander_has_target = true
		_wander_has_primary_target = true

	velocity = away_dir * (wander_speed * 1.15)
	move_and_slide()
	_wander_stuck_time = 0.0
	_has_progress_sample = true
	_last_progress_sample = global_position
	_last_move_dir = away_dir
	_set_princess_animation(away_dir)

	# Tiny pause after separating to reduce immediate re-contact jitter.
	_wander_wait_time_left = maxf(_wander_wait_time_left, 0.12)
	return true


func _handle_stuck_repath(delta: float) -> bool:
	if not _wander_has_target:
		_wander_stuck_time = 0.0
		_has_progress_sample = false
		return false

	if not _has_progress_sample:
		_has_progress_sample = true
		_last_progress_sample = global_position
		_wander_stuck_time = 0.0
		return false

	var moved := global_position.distance_to(_last_progress_sample)
	if moved >= wander_progress_epsilon:
		_last_progress_sample = global_position
		_wander_stuck_time = 0.0
		return false

	_wander_stuck_time += delta
	if _wander_stuck_time < wander_stuck_seconds:
		return false

	_wander_stuck_time = 0.0
	_last_progress_sample = global_position

	var preferred_dir := (_wander_target - global_position).normalized()
	if preferred_dir.length() <= 0.001:
		preferred_dir = _last_move_dir
	if preferred_dir.length() <= 0.001:
		preferred_dir = Vector2.RIGHT

	if not _pick_detour_target(preferred_dir, _wander_primary_target):
		_pick_new_wander_target()

	_wander_wait_time_left = 0.0
	return true


func _pick_new_wander_target() -> void:
	if _wander_checkpoints.size() > 0:
		var checkpoint_idx := randi() % _wander_checkpoints.size()
		
		# Avoid immediately returning to the same checkpoint
		if _wander_checkpoints.size() > 1:
			var attempts := 0
			while checkpoint_idx == _last_checkpoint_index and attempts < 5:
				checkpoint_idx = randi() % _wander_checkpoints.size()
				attempts += 1
		
		_last_checkpoint_index = checkpoint_idx
		_wander_target = _wander_checkpoints[checkpoint_idx]
		_wander_primary_target = _wander_target
		_wander_has_target = true
		_wander_has_primary_target = true
		return

	if _wander_polygon.size() >= 3:
		for _i in 40:
			var p := Vector2(
				randf_range(_wander_area.position.x, _wander_area.end.x),
				randf_range(_wander_area.position.y, _wander_area.end.y)
			)
			if Geometry2D.is_point_in_polygon(p, _wander_polygon):
				_wander_target = p
				_wander_primary_target = p
				_wander_has_target = true
				_wander_has_primary_target = true
				return

	_wander_target = Vector2(
		randf_range(_wander_area.position.x, _wander_area.end.x),
		randf_range(_wander_area.position.y, _wander_area.end.y)
	)
	_wander_primary_target = _wander_target
	_wander_has_target = true
	_wander_has_primary_target = true


func _is_obstacle_ahead(dir: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	var start := global_position
	var finish := start + dir * ahead_check_distance
	var query := PhysicsRayQueryParameters2D.create(start, finish)
	query.exclude = [self]
	var hit := space_state.intersect_ray(query)
	return not hit.is_empty()


func _pick_detour_target(forward_dir: Vector2, desired_target: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	var rays := maxi(3, detour_scan_rays)
	if rays % 2 == 0:
		rays += 1

	var best_point := Vector2.ZERO
	var best_score := -INF
	var half_angle := deg_to_rad(detour_scan_angle_degrees * 0.5)
	var has_desired := _wander_has_primary_target and desired_target.is_finite()
	var current_goal_distance := 0.0
	if has_desired:
		current_goal_distance = global_position.distance_to(desired_target)

	for i in range(rays):
		var t := 0.0 if rays <= 1 else float(i) / float(rays - 1)
		var angle_offset := lerpf(-half_angle, half_angle, t)
		var dir := forward_dir.rotated(angle_offset).normalized()

		var ray_end := global_position + dir * detour_scan_distance
		var query := PhysicsRayQueryParameters2D.create(global_position, ray_end)
		query.exclude = [self]
		var hit := space_state.intersect_ray(query)

		var clear_distance := detour_scan_distance
		if not hit.is_empty():
			var hit_pos: Vector2 = global_position
			if hit.has("position") and hit["position"] is Vector2:
				hit_pos = hit["position"]
			clear_distance = maxf(0.0, global_position.distance_to(hit_pos) - 8.0)

		if clear_distance <= ahead_check_distance * 0.55:
			continue

		var candidate := global_position + dir * (clear_distance * 0.85)
		if not _is_point_in_wander_space(candidate):
			continue

		# Favor longer clear paths while still preferring mostly-forward travel.
		var forward_bias := maxf(0.0, forward_dir.dot(dir))
		var score := clear_distance + (forward_bias * 24.0)
		if has_desired:
			# Strongly prefer detours that reduce remaining distance to the real goal.
			var goal_progress := current_goal_distance - candidate.distance_to(desired_target)
			score += goal_progress * 45.0
		if score > best_score:
			best_score = score
			best_point = candidate

	if best_score <= 0.0:
		return false

	_wander_target = best_point
	_wander_has_target = true
	return true


func _is_point_in_wander_space(point: Vector2) -> bool:
	if _wander_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, _wander_polygon)
	return _wander_area.has_point(point)


func _is_point_in_view(world_point: Vector2) -> bool:
	var to_point := world_point - global_position
	var dist := to_point.length()
	if dist > view_distance or dist <= 0.001:
		return false

	var dir := to_point / dist
	var facing := _last_move_dir
	if facing.length() <= 0.001:
		facing = Vector2.DOWN
	var dotv := facing.normalized().dot(dir)
	var min_dot := cos(deg_to_rad(view_angle_degrees * 0.5))
	if dotv < min_dot:
		return false

	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(global_position, world_point)
	query.exclude = [self]
	var hit := space_state.intersect_ray(query)
	return hit.is_empty()


func _set_princess_animation(move_dir: Vector2) -> void:
	if _sprite == null:
		return

	var sample := move_dir
	if sample == Vector2.ZERO:
		sample = _last_move_dir

	var anim := "idle-s"
	if move_dir == Vector2.ZERO:
		anim = _get_idle_anim(sample)
	else:
		anim = _get_walk_anim(sample)

	if _sprite.animation != anim:
		_sprite.play(anim)


func _get_walk_anim(d: Vector2) -> String:
	if d.y < -0.5 and absf(d.x) < 0.5:
		return "walk-n"
	if d.y > 0.5 and absf(d.x) < 0.5:
		return "walk-s"
	if d.x > 0.5 and absf(d.y) < 0.5:
		return "walk-e"
	if d.x < -0.5 and absf(d.y) < 0.5:
		return "walk-w"
	if d.x > 0.0 and d.y < 0.0:
		return "walk-ne"
	if d.x < 0.0 and d.y < 0.0:
		return "walk-nw"
	if d.x > 0.0 and d.y > 0.0:
		return "walk-se"
	return "walk-sw"


func _get_idle_anim(d: Vector2) -> String:
	if d.y < -0.5 and absf(d.x) < 0.5:
		return "idle-n"
	if d.y > 0.5 and absf(d.x) < 0.5:
		return "idle-s"
	if d.x > 0.5 and absf(d.y) < 0.5:
		return "idle-e"
	if d.x < -0.5 and absf(d.y) < 0.5:
		return "idle-w"
	if d.x > 0.0 and d.y < 0.0:
		return "idle-ne"
	if d.x < 0.0 and d.y < 0.0:
		return "idle-nw"
	if d.x > 0.0 and d.y > 0.0:
		return "idle-se"
	return "idle-sw"


func _draw() -> void:
	if not view_debug_visible:
		return

	var facing := _last_move_dir
	if facing.length() <= 0.001:
		facing = Vector2.DOWN

	var half_angle := deg_to_rad(view_angle_degrees * 0.5)
	var start_angle := facing.angle() - half_angle
	var end_angle := facing.angle() + half_angle
	var color := Color(0.3, 0.9, 0.75, 0.2)

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(0, 16):
		var t := float(i) / 15.0
		var a := lerpf(start_angle, end_angle, t)
		points.append(Vector2.RIGHT.rotated(a) * view_distance)
	points.append(Vector2.ZERO)

	draw_colored_polygon(points, color)


# Kept for compatibility with world.gd integration points.
func configure_princess_behavior(area_rect: Rect2, checkpoint_positions: Array[Vector2], polygon_points: PackedVector2Array = PackedVector2Array(), _flower_positions: Array[Vector2] = []) -> void:
	_wander_area = area_rect
	_wander_polygon = polygon_points
	_wander_checkpoints = checkpoint_positions
	_wander_has_target = false
	_last_checkpoint_index = -1  # Reset checkpoint cooldown


# Kept for compatibility with save loading hooks.
func apply_saved_state(data: Dictionary) -> void:
	_suppress_story_from_save = true

	if data.has("npc_position"):
		global_position = Vector2(float(data["npc_position"]["x"]), float(data["npc_position"]["y"]))

	_story_completed = bool(data.get("npc_story_completed", true))
	_story_sequence_started = bool(data.get("npc_story_sequence_started", false))
	_exploration_started = bool(data.get("npc_exploration_started", _story_completed))
	_return_sequence_started = bool(data.get("npc_return_sequence_started", false))
	_night_started = bool(data.get("npc_night_started", false))

	var saved_wander_enabled := bool(data.get("npc_wander_enabled", _exploration_started and not _return_sequence_started and not _night_started))
	_wander_enabled = saved_wander_enabled
	_wander_has_target = false
	_last_checkpoint_index = -1  # Reset checkpoint cooldown on load

	_clear_dialogue()
	if _player_ref and _player_ref.has_method("set_controls_enabled"):
		_player_ref.call("set_controls_enabled", true)


func get_save_state() -> Dictionary:
	return {
		"npc_story_completed": _story_completed,
		"npc_story_sequence_started": _story_sequence_started,
		"npc_exploration_started": _exploration_started,
		"npc_return_sequence_started": _return_sequence_started,
		"npc_night_started": _night_started,
		"npc_wander_enabled": _wander_enabled
	}
