extends Node2D

@onready var anchor: Node2D = %Anchor
@onready var ray: RayCast2D = %Ray
@onready var line: Line2D = %Line2D

var velocity := Vector2.ZERO
var gravity := Vector2(0, 980)
var rope_length_max := 600.0
var damping := 0.98
var rope_elasticity := 1280

var anchor_points := [Vector2(0,0),Vector2(0,0)]
var collider
@onready var debug: Control = %Debug

func _physics_process(delta: float) -> void:
	if anchor_points.size() > line.points.size():
		line.add_point(Vector2.ZERO)
	if line.points.size() > anchor_points.size():
		line.remove_point(0)
	assign_start_and_end()
	draw_segments()
	detect_collision_on_segments()
	
	if calculate_rope_total_length() > rope_length_max:
		global_position -= (global_position - anchor_points[anchor_points.size()-2]).normalized() * rope_elasticity * delta
	if calculate_rope_total_length() < rope_length_max:
		global_position += (global_position - anchor_points[anchor_points.size()-2]).normalized() * rope_elasticity * delta
	global_position += gravity * delta 
	

func calculate_rope_total_length() -> int:
	var length := 0.0
	for i in len(anchor_points):
		if i < anchor_points.size() - 1:
			length += anchor_points[i].distance_to(anchor_points[i+1])
	return length

func assign_start_and_end():
	anchor_points[0] = anchor.global_position 
	anchor_points[anchor_points.size() - 1] = global_position
	

func distribute_segments():
	pass

func add_segment(point:Vector2):
	anchor_points.append(point)
	anchor_points[anchor_points.size() - 2] = point
	pass

func detect_collision_on_segments():
	for i in len(anchor_points):
		if i > 0:
			#var a = anchor_points[i-1] - anchor_points[i] as Vector2
			var ray_param = PhysicsRayQueryParameters2D.new()
			ray_param.from = anchor_points[i-1]
			ray_param.to = anchor_points[i]
			ray_param.collide_with_areas = true
			var space_state = get_world_2d().direct_space_state
			var result = space_state.intersect_ray(ray_param) 
			if result:
				var exist := false
				for point: Vector2 in anchor_points:
					if point.distance_squared_to(result.get("position")) < 0.2:
						exist = true
				if not exist:
					add_segment(result.get("position"))
				
			
	pass

	
func draw_segments():
	for i in len(anchor_points):
		line.set_point_position(i, anchor_points[i])


func _process(delta: float) -> void:
	handle_player_controls(delta)
	
func handle_player_controls(delta):
	if Input.is_action_pressed("game_move_up"):
		rope_length_max -= delta * 130.0
	if Input.is_action_pressed("game_move_down"):
		rope_length_max += delta * 130.0
	
	if Input.is_action_pressed("game_shoot_left"):
		position.x += delta * 900.0
	if Input.is_action_pressed("game_shoot_right"):
		position.x -= delta * 900.0
