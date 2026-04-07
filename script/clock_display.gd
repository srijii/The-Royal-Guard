extends Control

var time_until_midnight := 120.0
var clock_radius := 40.0
var clock_center := Vector2(50, 50)

# Colors for day/night visualization
var day_color := Color(1.0, 1.0, 0.8, 1.0)  # Light yellowish for day
var night_color := Color(0.2, 0.2, 0.3, 1.0)  # Dark blue for night
var border_color := Color(0.3, 0.3, 0.3, 1.0)

func _ready() -> void:
	custom_minimum_size = Vector2(100, 100)
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Draw clock background (circle)
	var progress := clampf(1.0 - (time_until_midnight / 120.0), 0.0, 1.0)
	var bg_color := day_color.lerp(night_color, progress)
	draw_circle(clock_center, clock_radius, bg_color)
	
	# Draw clock border
	draw_circle(clock_center, clock_radius, border_color, false, 2.0)
	
	# Draw hour markers (12 positions)
	for i in range(12):
		var angle := (-PI / 2.0) + (i * TAU / 12.0)
		var outer := clock_center + Vector2(cos(angle), sin(angle)) * (clock_radius - 5)
		var inner := clock_center + Vector2(cos(angle), sin(angle)) * (clock_radius - 12)
		draw_line(inner, outer, Color.BLACK, 1.5)
	
	# Calculate hand angles (12 hours = full rotation)
	# Map 120 seconds to 12 hours cycle
	var total_cycle_seconds := 120.0
	var current_position := total_cycle_seconds - time_until_midnight
	var cycle_progress := fmod(current_position, total_cycle_seconds) / total_cycle_seconds
	
	# Hour hand (marks 24-hour day/night cycle)
	var hour_angle := (-PI / 2.0) + (cycle_progress * TAU)
	var hour_hand_length := clock_radius * 0.5
	var hour_hand_end := clock_center + Vector2(cos(hour_angle), sin(hour_angle)) * hour_hand_length
	draw_line(clock_center, hour_hand_end, Color.BLACK, 3.0)
	
	# Minute hand (faster indicator)
	var minute_angle := (-PI / 2.0) + (cycle_progress * TAU * 2.0)  # Faster rotation
	var minute_hand_length := clock_radius * 0.7
	var minute_hand_end := clock_center + Vector2(cos(minute_angle), sin(minute_angle)) * minute_hand_length
	draw_line(clock_center, minute_hand_end, Color(0.5, 0.5, 0.5, 1.0), 2.0)
	
	# Draw center dot
	draw_circle(clock_center, 3.0, Color.BLACK)
