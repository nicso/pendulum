# RopeRenderer.gd
extends Line2D
class_name LineRenderer

var control_points: Array[Vector2] = []

func update_rope_visual(points: Array[Vector2]):
	clear_points()
	
	# Lissage par spline de Bézier
	if points.size() >= 2:
		var smooth_points = create_smooth_curve(points)
		for point in smooth_points:
			add_point(point)

func create_smooth_curve(points: Array[Vector2]) -> Array[Vector2]:
	var smooth = []
	var resolution = 5  # Points entre chaque point de contrôle
	
	for i in range(points.size() - 1):
		for j in range(resolution):
			var t = float(j) / resolution
			var interpolated = points[i].lerp(points[i + 1], t)
			smooth.append(interpolated)
	
	smooth.append(points[-1])  # Dernier point
	return smooth
