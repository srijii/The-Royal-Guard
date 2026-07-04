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
var _player_hearts: Array[TextureRect] = []
var _heart_full_texture: Texture2D = null
var _heart_empty_texture: Texture2D = null
var _respawn_pending := false
var _ending_started := false
var _death_screen_visible := false
var _ending_layer: CanvasLayer = null
var _ending_fade_rect: ColorRect = null
var _ending_label: Label = null
var _death_layer: CanvasLayer = null
var _death_panel: PanelContainer = null
var _death_respawn_button: Button = null


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


func _configure_player_for_final_boss(player: Node2D) -> void:
	var max_health: int = maxi(10, boss_player_hearts * 10)
	player.set("max_health", max_health)
	player.set("current_health", max_health)

	# Final boss arena uses unlimited sprint by disabling energy drain.
	player.set("energy_drain_per_second", 0.0)
	if player.has_method("get"):
		var max_energy_value := float(player.get("max_energy"))
		player.set("_energy_value", max_energy_value)

	var on_died := Callable(self, "_on_player_died")
	if player.has_signal("died") and not player.is_connected("died", on_died):
		player.connect("died", on_died)

	_setup_potion_spawner()


func _setup_life_ui() -> void:
	var hud := get_node_or_null("BossHud") as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = "BossHud"
		hud.layer = 100
		add_child(hud)

	var hearts_row := hud.get_node_or_null("HeartsRow") as HBoxContainer
	if hearts_row == null:
		hearts_row = HBoxContainer.new()
		hearts_row.name = "HeartsRow"
		hearts_row.position = Vector2(16, 12)
		hearts_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		hearts_row.add_theme_constant_override("separation", 4)
		hud.add_child(hearts_row)

	_heart_full_texture = _build_heart_texture(Color(0.95, 0.18, 0.22, 1.0))
	_heart_empty_texture = _build_heart_texture(Color(0.35, 0.35, 0.35, 0.95))

	var total_hearts: int = maxi(1, boss_player_hearts)
	_player_hearts.clear()
	for i in range(total_hearts):
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(18, 18)
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.texture = _heart_empty_texture
		hearts_row.add_child(heart)
		_player_hearts.append(heart)


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
		heart.texture = _heart_full_texture if i < filled_hearts else _heart_empty_texture


func _build_heart_texture(tint: Color) -> Texture2D:
	var image := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(14):
		for x in range(14):
			var px: int = x - 6
			var py: int = y - 4
			var left_circle: bool = (px + 2) * (px + 2) + py * py <= 9
			var right_circle: bool = (px - 2) * (px - 2) + py * py <= 9
			var diamond: bool = (absi(px) + absi(py - 3) <= 7) and (py >= 1)
			if left_circle or right_circle or diamond:
				image.set_pixel(x, y, tint)

	return ImageTexture.create_from_image(image)


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


func _unhandled_input(event: InputEvent) -> void:
	if not _death_screen_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER or key_event.keycode == KEY_SPACE:
			_on_death_respawn_pressed()
			get_viewport().set_input_as_handled()


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
		end_label.offset_top = -60.0
		end_label.offset_right = 420.0
		end_label.offset_bottom = 60.0
		end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		end_label.add_theme_font_size_override("font_size", 34)
		end_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		end_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		end_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_label.text = "you captured the princess ring."
		layer.add_child(end_label)

	_ending_layer = layer
	_ending_fade_rect = fade_rect
	_ending_label = end_label


func _on_queen_ring_collected() -> void:
	if _ending_started:
		return
	_ending_started = true
	_respawn_pending = true
	if _ending_layer != null:
		_ending_layer.visible = true

	if _ending_label != null:
		_ending_label.text = "you captured the princess ring."
		_ending_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
		_ending_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	if _player != null and _player.has_method("set_controls_enabled"):
		_player.call("set_controls_enabled", false)

	get_tree().paused = true

	if _ending_fade_rect != null:
		var fade_tween := _create_ending_tween()
		fade_tween.tween_property(_ending_fade_rect, "color", Color(0.0, 0.0, 0.0, 1.0), 0.3)

	if _ending_label != null:
		var label_tween := _create_ending_tween()
		label_tween.tween_property(_ending_label, "modulate:a", 1.0, 0.6)
		label_tween.tween_interval(2.0)
		label_tween.tween_callback(Callable(self, "_show_the_end"))


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


func _show_the_end() -> void:
	if not _ending_started or _ending_label == null:
		return

	var fade_tween := _create_ending_tween()
	fade_tween.tween_property(_ending_label, "modulate:a", 0.0, 0.8)
	fade_tween.tween_callback(func() -> void:
		if _ending_label == null:
			return
		_ending_label.text = "THE END"
		_ending_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2, 1.0))
	)
	fade_tween.tween_property(_ending_label, "modulate:a", 1.0, 0.8)


func _create_ending_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


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

	var available_types := []
	for ptype in ["health", "strength", "energy"]:
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

	var miko := get_node_or_null("miko")
	var spawn_pos := global_position
	if miko != null:
		spawn_pos = miko.global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80))
	else:
		spawn_pos = global_position + Vector2(randf_range(100, 300), randf_range(100, 300))

	_spawn_potion_at(chosen_type, tint, spawn_pos)


func _spawn_potion_at(potion_type: String, tint: Color, position: Vector2) -> void:
	var pickup := Area2D.new()
	pickup.name = "ArenaPotionDrop"
	pickup.global_position = position
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

	pickup.body_entered.connect(func(body: Node) -> void:
		if body == null or not is_instance_valid(body):
			return
		if pickup == null or not is_instance_valid(pickup):
			return
		if body.has_method("add_potion_item"):
			body.call("add_potion_item", potion_type)
			pickup.queue_free()
	)

	add_child(pickup)
	call_deferred("_check_potion_auto_collect", pickup, potion_type)

	var tween := pickup.create_tween()
	tween.set_loops()
	tween.tween_property(pickup, "position:y", pickup.position.y - 5.0, 0.45)
	tween.tween_property(pickup, "position:y", pickup.position.y + 5.0, 0.45)


func _check_potion_auto_collect(pickup: Area2D, potion_type: String) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	await get_tree().physics_frame
	if pickup == null or not is_instance_valid(pickup):
		return
	for body in pickup.get_overlapping_bodies():
		if body != null and is_instance_valid(body) and body.has_method("add_potion_item"):
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
