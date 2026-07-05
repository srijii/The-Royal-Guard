extends Node

func choose(array: Array):
	array.shuffle()
	return array.front()


static func queue_free_node(ref: WeakRef) -> void:
	var node := ref.get_ref() as Node
	if node != null and is_instance_valid(node):
		node.queue_free()


func spawn_blood_effect(position: Vector2) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root

	var blood := Node2D.new()
	blood.global_position = position
	root.add_child(blood)

	var root_tween := create_tween()
	root_tween.set_parallel(true)
	for i in range(10):
		var drop := Polygon2D.new()
		var size := randf_range(2.0, 6.0)
		drop.polygon = PackedVector2Array([
			Vector2(-size, -size * 0.4),
			Vector2(0, -size * 0.8),
			Vector2(size, -size * 0.4),
			Vector2(size * 0.6, size * 0.4),
			Vector2(0, size * 0.8),
			Vector2(-size * 0.6, size * 0.4),
		])
		drop.color = Color(0.6, 0.05, 0.05, 0.9)
		drop.global_position = Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
		blood.add_child(drop)

		var spread := Vector2(randf_range(-30.0, 30.0), randf_range(-40.0, 10.0))
		root_tween.tween_property(drop, "global_position", drop.global_position + spread, 0.3)
		root_tween.tween_property(drop, "modulate:a", 0.0, 0.3)

	root_tween.finished.connect(Helpers.queue_free_node.bind(weakref(blood)))


func spawn_bone_effect(position: Vector2) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root

	var bone_group := Node2D.new()
	bone_group.global_position = position
	root.add_child(bone_group)

	var root_tween := create_tween()
	root_tween.set_parallel(true)
	for i in range(8):
		var chip := Polygon2D.new()
		var w := randf_range(2.0, 5.0)
		var h := randf_range(1.0, 3.0)
		chip.polygon = PackedVector2Array([
			Vector2(-w, -h),
			Vector2(w, -h * 0.5),
			Vector2(w * 0.6, h),
			Vector2(-w * 0.4, h * 0.6),
		])
		chip.color = Color(0.85, 0.80, 0.70, 0.95)
		chip.global_position = Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		bone_group.add_child(chip)

		var spread := Vector2(randf_range(-25.0, 25.0), randf_range(-35.0, 5.0))
		root_tween.tween_property(chip, "global_position", chip.global_position + spread, 0.4)
		root_tween.tween_property(chip, "rotation", randf_range(-3.0, 3.0), 0.4)
		root_tween.tween_property(chip, "modulate:a", 0.0, 0.4)

	root_tween.finished.connect(Helpers.queue_free_node.bind(weakref(bone_group)))


func spawn_blood_stain(position: Vector2) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root

	var stain := Polygon2D.new()
	var r := randf_range(3.0, 7.0)
	stain.polygon = PackedVector2Array([
		Vector2(-r, -r * 0.6),
		Vector2(r * 0.3, -r * 0.8),
		Vector2(r, -r * 0.2),
		Vector2(r, r * 0.4),
		Vector2(0, r * 0.8),
		Vector2(-r * 0.7, r * 0.3),
	])
	stain.color = Color(0.4, 0.03, 0.03, 0.35)
	stain.global_position = position + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	stain.rotation = randf_range(-0.5, 0.5)
	root.add_child(stain)

	var tween := create_tween()
	tween.tween_property(stain, "modulate:a", 0.0, 4.0).set_delay(6.0)
	tween.finished.connect(Helpers.queue_free_node.bind(weakref(stain)))
