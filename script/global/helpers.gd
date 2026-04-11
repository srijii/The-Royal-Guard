extends Node

func choose(array: Array):
	array.shuffle()
	return array.front()
