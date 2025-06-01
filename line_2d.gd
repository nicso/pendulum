extends Line2D
class_name Line

var target1 : Node2D
var target2 : Node2D


func _ready() -> void:	
	points = [ Vector2.ZERO, Vector2.ZERO ]


func _process(delta: float) -> void:
	if is_instance_valid(target1) and is_instance_valid(target2):
		points[0] = to_local(target1.global_position)
		points[1] = to_local(target2.global_position)
