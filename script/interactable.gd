extends CharacterBody2D

@export var interaction_radius := 72.0
@export var interaction_name := "Item"
@export var idle_animation := "idle_s"
@export var interact_animation := "interact"
@export var post_interact_animation := ""
@export var return_to_idle_after_interact := true

signal interaction_started(interactable_name: String)
signal interaction_completed(interactable_name: String)

var _player_ref: Node2D = null
var _sprite: AnimatedSprite2D = null
var _in_interaction := false


func _ready() -> void:
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	
	# Find player
	var world := get_parent()
	if world:
		_player_ref = world.get_node_or_null("player") as Node2D
	
	# Play idle animation
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(idle_animation):
		_sprite.play(idle_animation)


func is_player_in_range() -> bool:
	if _player_ref == null:
		return false
	return global_position.distance_to(_player_ref.global_position) <= interaction_radius


func is_in_interaction() -> bool:
	return _in_interaction


func try_interact() -> bool:
	if not is_player_in_range() or _in_interaction:
		return false
	
	_in_interaction = true
	interaction_started.emit(interaction_name)
	
	if _sprite and _sprite.sprite_frames.has_animation(interact_animation):
		_sprite.play(interact_animation)
		await _sprite.animation_finished
	
	# Play post-interact animation if specified
	if post_interact_animation != "" and _sprite and _sprite.sprite_frames.has_animation(post_interact_animation):
		_sprite.play(post_interact_animation)
		if _sprite.sprite_frames.get_animation_loop(post_interact_animation):
			# If post-interact is a loop, wait indefinitely (or you can add timeout logic)
			pass
		else:
			# If post-interact is a one-shot, wait for it to finish
			await _sprite.animation_finished
	elif return_to_idle_after_interact and _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(idle_animation):
		_sprite.play(idle_animation)
	
	_in_interaction = false
	interaction_completed.emit(interaction_name)
	
	return true


func get_interaction_name() -> String:
	return interaction_name


func set_interaction_name(item_name: String) -> void:
	interaction_name = item_name
