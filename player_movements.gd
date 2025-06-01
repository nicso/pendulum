extends Node2D

@onready var anchor: Node2D = %Anchor
@onready var ray: RayCast2D = %Ray
@onready var line: Line = %Line2D

var velocity := Vector2.ZERO
var gravity := Vector2(0, 4980)
var rope_length :=400.0
var damping := 0.98

var anchor_points := [(0.0)]
var collider
@onready var debug: Control = %Debug


func _process(delta: float) -> void:
	if anchor == null:
		pass
		
	anchor_points[0] = anchor.global_position
	velocity += gravity * delta
	position += velocity * delta

	var to_node = position - anchor_points.back()
	var direction = to_node.normalized()
	var current_length = to_node.length()

	if current_length != 0:
		position = anchor_points.back() + direction * rope_length
		var tangent = Vector2(-direction.y, direction.x)
		var tangential_velocity = velocity.project(tangent)
		var radial_velocity = velocity.project(direction)
		var dot = velocity.normalized().dot(direction)
		radial_velocity *= 1.0 - clamp(abs(dot), 0.0, 1.0) * 0.2  # 0.3 = force du frein
		velocity = tangential_velocity + radial_velocity
		

		velocity *= damping
		
		# cast for obstacles

		ray.target_position = anchor_points.back() - global_position
		
		if ray.is_colliding(): 
			if ray.get_collision_point().y != anchor_points.back()[1]:
				anchor_points.append(ray.get_collision_point())
				var col = ray.get_collision_point()
		elif anchor_points.size() > 1:
			anchor_points.pop_back()
		if anchor_points.size() > 1:
			var last_segment := ray.get_collision_point() - global_position
			var previous_segment =  anchor_points[anchor_points.size() - 2] - anchor_points[anchor_points.size() - 1]
			var dot_ = last_segment.normalized().dot(previous_segment.normalized())
			var dbg = debug.get_child(0) as Label
			dbg.text =  str(dot_)
			print(dot_ )
			
			if dot_ < 0:
				anchor_points.pop_back()
		
		# draw rope
		if anchor:
			line.target1 = self
			line.target2 = anchor
		
		if Input.is_action_pressed("game_move_up"):
			rope_length -= delta * 130.0
		if Input.is_action_pressed("game_move_down"):
			rope_length += delta * 130.0
		
		if Input.is_action_pressed("game_shoot_left"):
			position.x += delta * 900.0
		if Input.is_action_pressed("game_shoot_right"):
			position.x -= delta * 900.0
