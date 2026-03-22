extends Node

var shooting := 1.0
var max_shooting_level := 15.0
var hits := 0.0

func shooting_level(hit := 1.0) -> void:
	hits += hit
	var upper := pow((shooting + 1.0) * 2.0, 3.0)
	if hits > upper:
		shooting += 1.0
