extends Node2D

@export var SPEED:= 500.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	var direction = Input.get_axis("game_move_left","game_move_right")
	if direction:
		position.x += direction * SPEED * delta
