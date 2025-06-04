# RopeSystem.gd
extends Node2D

class_name RopeSystem

# Points de la corde (ancre -> points de pliage -> joueur)
var rope_points: Array[Vector2] = []

# Références
@export var anchor: Node2D
@export var player: Player
@export var rope_length: float = 800.0
@export var rope_color: Color = Color.MAGENTA
@export var rope_width: float = 13.0
@export var debug_points: bool = false

# Paramètres de détection
@export var collision_margin: float = 1.0
@export var max_iterations: int = 50       
@export var corner_detection_distance: float = 10.0
@export var point_contact_radius: float = 8.0  # Rayon pour vérifier le contact des points
@export var min_point_distance: float = 2.0  # Distance minimale entre points consécutifs

# Paramètres de gravité
@export var gravity: float = 1980.0
@export var damping: float = 0.96

# Variables pour la physique du dernier point de la corde
var last_point_velocity: Vector2 = Vector2.ZERO

# Stabilité temporelle pour éviter les oscillations
var point_removal_cooldown: Dictionary = {}
var cooldown_frames: int = 10

# SUPPRIMÉ : var obstacles: Array[Node2D] = []
# Plus besoin de stocker les obstacles !

func _ready():
	# Initialiser avec deux points : ancre et joueur
	if anchor and player:
		rope_points = [anchor.global_position, player.global_position]
	
	# SUPPRIMÉ : call_deferred("get_obstacles")
	# Plus besoin de récupérer les obstacles au démarrage !

func _process(delta):
	if anchor and player and rope_points.size() >= 2:
		apply_gravity_to_last_point(delta)
		update_rope_physics()
		fix_rope_penetrations()
		handle_player_physics_with_rope_constraint(delta)
		queue_redraw()

func handle_player_physics_with_rope_constraint(delta: float):
	"""Gère la physique du joueur en tenant compte des collisions ET de la contrainte de corde"""
	if not player:
		return
	
	var rope_target_position = rope_points[rope_points.size() - 1]
	
	if player is CharacterBody2D:
		handle_character_body_with_rope(player, rope_target_position, delta)
	else:
		handle_manual_collision_with_rope(rope_target_position, delta)

func handle_character_body_with_rope(character_body: CharacterBody2D, rope_target: Vector2, delta: float):
	"""Gère un CharacterBody2D avec contrainte de corde"""
	var desired_movement = rope_target - character_body.global_position
	var max_distance = rope_length * 0.99
	var current_rope_length = calculate_rope_length_to_player()
	
	if current_rope_length + desired_movement.length() > max_distance:
		var available_distance = max_distance - current_rope_length
		if available_distance > 0:
			desired_movement = desired_movement.normalized() * min(desired_movement.length(), available_distance)
		else:
			desired_movement = Vector2.ZERO
	
	character_body.velocity = desired_movement / delta
	character_body.move_and_slide()
	rope_points[rope_points.size() - 1] = character_body.global_position
	
	var actual_movement = character_body.global_position - (rope_target - desired_movement)
	last_point_velocity = actual_movement / delta

func handle_manual_collision_with_rope(rope_target: Vector2, delta: float):
	"""Gère les collisions manuellement pour les nœuds non-CharacterBody2D"""
	if not player:
		return
	
	var start_position = player.global_position
	var desired_position = rope_target
	
	var collision_info = check_player_collision(start_position, desired_position)
	
	if collision_info.has_collision:
		player.global_position = collision_info.safe_position
		var normal = collision_info.normal
		last_point_velocity = last_point_velocity - 2 * last_point_velocity.dot(normal) * normal
		last_point_velocity *= 0.8
	else:
		player.global_position = desired_position
	
	rope_points[rope_points.size() - 1] = player.global_position

func check_player_collision(start: Vector2, end: Vector2) -> Dictionary:
	"""Vérifie les collisions du joueur en temps réel (exclut le joueur lui-même)"""
	var result = {"has_collision": false, "safe_position": end, "normal": Vector2.ZERO}
	
	if not player:
		return result
	
	var collision_shape = get_player_collision_shape()
	if not collision_shape:
		return result
	
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return result
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = Transform2D(0, end + collision_shape.position)
	query.collision_mask = get_rope_collision_mask()  # Utilise un masque spécifique pour la corde
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclure le joueur des détections
	query.exclude = [player.get_rid()]
	
	var collisions = space_state.intersect_shape(query)
	
	if collisions.size() > 0:
		result.has_collision = true
		var ray_result = cast_ray(start, end)
		
		if not ray_result.is_empty():
			result.normal = ray_result.normal
			result.safe_position = ray_result.position - (end - start).normalized() * 5.0
		else:
			result.safe_position = start
	
	return result

func get_player_collision_shape() -> CollisionShape2D:
	"""Récupère la forme de collision du joueur"""
	if not player:
		return null
	
	for child in player.get_children():
		if child is CollisionShape2D:
			return child
	return null

func validate_rope_points_contact():
	"""Vérifie que chaque point intermédiaire de la corde est encore en contact avec un obstacle"""
	# Ne vérifier que les points intermédiaires (ni l'ancre ni le joueur)
	var i = 1
	while i < rope_points.size() - 1:
		var point = rope_points[i]
		
		# Vérifier le cooldown pour ce point
		if point_removal_cooldown.has(i):
			i += 1
			continue
		
		# Vérifier si le point est encore en contact avec un obstacle
		if not is_point_in_contact_with_obstacle(point):
			# Le point n'est plus en contact, le supprimer
			rope_points.remove_at(i)
			
			# Ajuster les index des cooldowns existants
			var new_cooldowns = {}
			for key in point_removal_cooldown.keys():
				if key > i:
					new_cooldowns[key - 1] = point_removal_cooldown[key]
				elif key < i:
					new_cooldowns[key] = point_removal_cooldown[key]
			point_removal_cooldown = new_cooldowns
			
			# Ne pas incrémenter i car on a supprimé un élément
		else:
			i += 1

func is_point_in_contact_with_obstacle(point: Vector2) -> bool:
	"""Vérifie si un point est encore en contact avec un obstacle via un shape cast"""
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return false
	
	# Créer une forme circulaire pour le test de contact
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = point_contact_radius
	
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = circle_shape
	query.transform = Transform2D(0, point)
	query.collision_mask = get_rope_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclure le joueur des détections
	if player:
		query.exclude = [player.get_rid()]
	
	var collisions = space_state.intersect_shape(query)
	
	# Pas besoin de queue_free() pour les ressources - le garbage collector s'en charge
	
	return collisions.size() > 0
	"""Détermine le masque de collision à utiliser pour le joueur"""
	# Utilise le masque du joueur s'il existe, sinon le masque par défaut
	if player and player.has_method("get_collision_mask"):
		return player.get_collision_mask()
	return 1  # Masque par défaut

func get_rope_collision_mask() -> int:
	"""Détermine le masque de collision spécifique pour la corde (obstacles statiques uniquement)"""
	# Pour la corde, on veut généralement détecter seulement les obstacles statiques
	# Exclure les autres joueurs, ennemis, projectiles, etc.
	# Vous pouvez ajuster cette valeur selon votre configuration de layers
	return 1  # Layer des obstacles statiques

func calculate_rope_length_to_player() -> float:
	"""Calcule la longueur de corde jusqu'à l'avant-dernier point"""
	if rope_points.size() < 2:
		return 0.0
	
	var length = 0.0
	for i in range(rope_points.size() - 2):
		length += rope_points[i].distance_to(rope_points[i + 1])
	
	return length

# SUPPRIMÉ : func get_obstacles()
# Plus besoin de cette fonction !

func apply_gravity_to_last_point(delta: float):
	"""Applique la gravité uniquement au dernier point de la corde"""
	last_point_velocity.y += gravity * delta
	last_point_velocity *= damping
	
	var desired_last_position = rope_points[rope_points.size() - 1] + last_point_velocity * delta
	rope_points[rope_points.size() - 1] = desired_last_position

func update_rope_physics():
	"""Met à jour la physique de la corde"""
	if not anchor:
		return
	
	rope_points[0] = anchor.global_position
	
	# NOUVEAU : Vérifier que les points intermédiaires sont encore en contact avec des obstacles
	validate_rope_points_contact()
	
	clean_unnecessary_points()
	add_missing_collision_points()
	constrain_rope_length()

func fix_rope_penetrations():
	"""Corrige les pénétrations de la corde dans les obstacles"""
	var max_fixes = 10
	var fixes_applied = 0
	
	while fixes_applied < max_fixes:
		var penetration_fixed = false
		
		for i in range(rope_points.size() - 1):
			var start_point = rope_points[i]
			var end_point = rope_points[i + 1]
			
			var collision_info = get_detailed_collision_info(start_point, end_point)
			
			if collision_info.has_collision:
				var bypass_point = find_best_bypass_point(start_point, end_point, collision_info)
				
				if bypass_point != Vector2.ZERO:
					rope_points.insert(i + 1, bypass_point)
					penetration_fixed = true
					break
		
		if not penetration_fixed:
			break
		
		fixes_applied += 1

func get_detailed_collision_info(start: Vector2, end: Vector2) -> Dictionary:
	"""Obtient des informations détaillées sur la collision en temps réel (exclut le joueur)"""
	var result = {"has_collision": false, "collision_point": Vector2.ZERO, "normal": Vector2.ZERO, "collider": null}
	
	var collision = cast_ray(start, end)
	
	if not collision.is_empty() and collision.has("collider"):
		var collider = collision.collider
		
		# Double vérification : s'assurer que le collider n'est pas le joueur
		if is_instance_valid(collider) and collider != player:
			result.has_collision = true
			result.collision_point = collision.position
			result.normal = collision.normal
			result.collider = collider
	
	return result

func cast_ray(start: Vector2, end: Vector2) -> Dictionary:
	"""Lance un rayon et retourne les informations de collision (exclut le joueur)"""
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return {}
	
	var query = PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = get_rope_collision_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclure le joueur des détections de collision
	if player:
		query.exclude = [player.get_rid()]
	
	return space_state.intersect_ray(query)

func find_best_bypass_point(start: Vector2, end: Vector2, collision_info: Dictionary) -> Vector2:
	"""Trouve le meilleur point pour contourner un obstacle"""
	var collision_point = collision_info.collision_point
	var normal = collision_info.normal
	var collider = collision_info.collider
	
	if not is_instance_valid(collider):
		return Vector2.ZERO
	
	# Essayer de trouver les coins de l'obstacle
	var corner_points = find_obstacle_corners(collider)
	
	if corner_points.size() > 0:
		var best_corner = find_best_corner(start, end, corner_points)
		if best_corner != Vector2.ZERO:
			return best_corner
	
	# Fallback : utiliser la normale
	var bypass_point = collision_point + normal * (collision_margin * 2)
	
	if is_path_clear(start, bypass_point) and is_path_clear(bypass_point, end):
		return bypass_point
	
	return Vector2.ZERO

func find_best_corner(start: Vector2, end: Vector2, corners: Array[Vector2]) -> Vector2:
	"""Trouve le meilleur coin pour le contournement"""
	var best_corner = Vector2.ZERO
	var best_distance = INF
	
	for corner in corners:
		if is_path_clear(start, corner) and is_path_clear(corner, end):
			var distance = start.distance_to(corner) + corner.distance_to(end)
			if distance < best_distance:
				best_distance = distance
				best_corner = corner
	
	return best_corner

func is_path_clear(start: Vector2, end: Vector2) -> bool:
	"""Vérifie si le chemin entre deux points est libre"""
	var collision = cast_ray(start, end)
	return collision.is_empty()

func find_obstacle_corners(collider: Node2D) -> Array[Vector2]:
	"""Trouve les coins d'un obstacle en temps réel (exclut le joueur)"""
	var corners: Array[Vector2] = []
	
	# Ne pas traiter le joueur comme un obstacle
	if not is_instance_valid(collider) or collider == player:
		return corners
	
	var collision_shape = get_collider_shape(collider)
	if not collision_shape:
		return corners
	
	var shape = collision_shape.shape
	var transform = collider.global_transform * collision_shape.transform
	
	if shape is RectangleShape2D:
		corners = get_rectangle_corners(shape, transform)
	elif shape is CircleShape2D:
		corners = get_circle_corners(shape, transform)
	# Ajouter d'autres formes si nécessaire
	
	return corners

func get_collider_shape(collider: Node2D) -> CollisionShape2D:
	"""Récupère la forme de collision d'un collider"""
	for child in collider.get_children():
		if child is CollisionShape2D:
			return child
	return null

func get_rectangle_corners(shape: RectangleShape2D, transform: Transform2D) -> Array[Vector2]:
	"""Calcule les coins d'un rectangle avec marge"""
	var corners: Array[Vector2] = []
	var size = shape.size
	var half_size = size * 0.5
	
	# Les 4 coins du rectangle
	var base_corners = [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	]
	
	for corner in base_corners:
		var world_corner = transform * corner
		var center = transform.origin
		var direction = (world_corner - center).normalized()
		corners.append(world_corner + direction * collision_margin)
	
	return corners

func get_circle_corners(shape: CircleShape2D, transform: Transform2D) -> Array[Vector2]:
	"""Génère des points de contournement pour un cercle"""
	var corners: Array[Vector2] = []
	var radius = shape.radius + collision_margin
	var center = transform.origin
	
	# Générer 8 points autour du cercle
	for i in range(8):
		var angle = i * PI / 4.0
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		corners.append(point)
	
	return corners

func constrain_rope_length():
	"""Contraint la corde selon sa longueur maximale"""
	var total_length = calculate_rope_length()
	
	if total_length > rope_length:
		var old_last_point = rope_points[rope_points.size() - 1]
		rope_points = limit_rope_length(rope_points, rope_length)
		var new_last_point = rope_points[rope_points.size() - 1]
		
		if rope_points.size() >= 2:
			var rope_direction = (rope_points[rope_points.size() - 1] - rope_points[rope_points.size() - 2]).normalized()
			var tangent = Vector2(-rope_direction.y, rope_direction.x)
			
			last_point_velocity = tangent * last_point_velocity.dot(tangent)
			
			var constraint_force = (new_last_point - old_last_point).length()
			if constraint_force > 0:
				var bounce_direction = (new_last_point - old_last_point).normalized()
				last_point_velocity += bounce_direction * constraint_force * 0.1

func clean_unnecessary_points():
	"""Supprime les points de pliage qui ne sont plus nécessaires avec stabilité"""
	var keys_to_remove = []
	for key in point_removal_cooldown.keys():
		point_removal_cooldown[key] -= 1
		if point_removal_cooldown[key] <= 0:
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		point_removal_cooldown.erase(key)
	
	var i = 1
	while i < rope_points.size() - 1:
		var prev_point = rope_points[i - 1]
		var current_point = rope_points[i]
		var next_point = rope_points[i + 1]
		
		if point_removal_cooldown.has(i):
			i += 1
			continue
		
		var can_connect_directly = is_path_clear(prev_point, next_point)
		
		if can_connect_directly:
			var segment1_length = prev_point.distance_to(current_point)
			var segment2_length = current_point.distance_to(next_point)

			var direct_distance = prev_point.distance_to(next_point)
			var current_path_distance = prev_point.distance_to(current_point) + current_point.distance_to(next_point)
			
			var distance_ratio = direct_distance / current_path_distance
			var line_to_point_distance = distance_point_to_line(current_point, prev_point, next_point)
			
			var max_distance_reduction = 0.95
			var max_deviation = 200.0
			if segment1_length < min_point_distance or segment2_length < min_point_distance:
				# Conditions supplémentaires déjà vérifiées (ratio + déviation)
				if distance_ratio > max_distance_reduction and line_to_point_distance < max_deviation:
					# Suppression autorisée
					rope_points.remove_at(i)
			if distance_ratio > max_distance_reduction and line_to_point_distance < max_deviation:
				rope_points.remove_at(i)
				
				var new_cooldowns = {}
				for key in point_removal_cooldown.keys():
					if key > i:
						new_cooldowns[key - 1] = point_removal_cooldown[key]
					elif key < i:
						new_cooldowns[key] = point_removal_cooldown[key]
				point_removal_cooldown = new_cooldowns
			else:
				i += 1
		else:
			i += 1

func add_missing_collision_points():
	"""Ajoute de nouveaux points de collision là où c'est nécessaire"""
	var i = 0
	while i < rope_points.size() - 1 and rope_points.size() < max_iterations:
		var start_point = rope_points[i]
		var end_point = rope_points[i + 1]
		
		var collision_result = find_collision_on_segment(start_point, end_point)
		
		if collision_result.has_collision:
			rope_points.insert(i + 1, collision_result.contact_point)
			point_removal_cooldown[i + 1] = cooldown_frames
			
			var new_cooldowns = {}
			for key in point_removal_cooldown.keys():
				if key > i + 1:
					new_cooldowns[key + 1] = point_removal_cooldown[key]
				else:
					new_cooldowns[key] = point_removal_cooldown[key]
			point_removal_cooldown = new_cooldowns
			
			i += 2
		else:
			i += 1

func find_collision_on_segment(start: Vector2, end: Vector2) -> Dictionary:
	"""Trouve une collision sur un segment spécifique (exclut le joueur)"""
	var result = {"has_collision": false, "contact_point": Vector2.ZERO}
	
	var collision = cast_ray(start, end)
	
	if collision.is_empty() or not collision.has("collider"):
		return result
	
	var collider = collision.collider
	
	# Vérifier que le collider est valide ET n'est pas le joueur
	if not is_instance_valid(collider) or collider == player:
		return result
	
	var collision_point = collision.position
	var normal = collision.normal
	var contact_point = collision_point + normal * collision_margin
	
	result.has_collision = true
	result.contact_point = contact_point
	return result

func calculate_rope_length() -> float:
	"""Calcule la longueur totale de la corde"""
	var length = 0.0
	for i in range(rope_points.size() - 1):
		length += rope_points[i].distance_to(rope_points[i + 1])
	return length

func limit_rope_length(points: Array[Vector2], max_length: float) -> Array[Vector2]:
	"""Limite la longueur de la corde en ajustant les points"""
	if points.size() < 2:
		return points
	
	var new_points: Array[Vector2] = [points[0]]
	var current_length = 0.0
	
	for i in range(1, points.size()):
		var segment_length = new_points[new_points.size() - 1].distance_to(points[i])
		
		if current_length + segment_length <= max_length:
			new_points.append(points[i])
			current_length += segment_length
		else:
			var remaining_length = max_length - current_length
			if remaining_length > 0:
				var direction = (points[i] - new_points[new_points.size() - 1]).normalized()
				var final_point = new_points[new_points.size() - 1] + direction * remaining_length
				new_points.append(final_point)
			break
	
	return new_points

func _draw():
	"""Dessine la corde avec lissage réaliste"""
	if rope_points.size() < 2:
		return
	
	# Dessiner la corde lissée de façon réaliste
	_draw_realistic_rope()
	
	# Debug points (optionnel)
	if debug_points:
		for i in range(1, rope_points.size() - 1):
			var point = to_local(rope_points[i])
			draw_circle(point, 4, Color.RED)
	
	# Points de début et fin
	if rope_points.size() > 0:
		draw_circle(to_local(rope_points[0]), 6, Color.GREEN)
		draw_circle(to_local(rope_points[rope_points.size() - 1]), 6, Color.BLUE)

func _draw_realistic_rope():
	"""Dessine une corde avec un lissage qui respecte la physique"""
	if rope_points.size() < 2:
		return
	
	# Option 1: Lissage simple avec contraintes physiques
	_draw_constrained_smooth_rope()

func _draw_constrained_smooth_rope():
	"""Lissage avec contraintes pour éviter les boucles non réalistes"""
	var segments_per_curve = 28
	var smooth_points = []
	
	for i in range(rope_points.size() - 1):
		var p1 = to_local(rope_points[i])
		var p2 = to_local(rope_points[i + 1])
		
		# Calculer la direction générale du segment
		var segment_direction = (p2 - p1).normalized()
		var segment_length = p1.distance_to(p2)
		
		# Points de contrôle pour une courbe douce mais réaliste
		var control_strength = min(segment_length * 0.25, 30.0)  # Limiter la courbure
		
		var control1: Vector2
		var control2: Vector2
		
		if i > 0:
			var p0 = to_local(rope_points[i - 1])
			var incoming_dir = (p1 - p0).normalized()
			# Adoucir la transition entre les segments
			var smooth_dir = (incoming_dir + segment_direction).normalized()
			control1 = p1 + smooth_dir * control_strength
		else:
			control1 = p1 + segment_direction * control_strength * 0.5
		
		if i < rope_points.size() - 2:
			var p3 = to_local(rope_points[i + 2])
			var outgoing_dir = (p3 - p2).normalized()
			var smooth_dir = (segment_direction + outgoing_dir).normalized()
			control2 = p2 - smooth_dir * control_strength
		else:
			control2 = p2 - segment_direction * control_strength * 0.5
		
		# Générer les points de la courbe de Bézier cubique
		for j in range(segments_per_curve):
			var t = float(j) / float(segments_per_curve)
			var point = _bezier_cubic(p1, control1, control2, p2, t)
			smooth_points.append(point)
	
	# Ajouter le dernier point
	smooth_points.append(to_local(rope_points[rope_points.size() - 1]))
	
	# Dessiner les segments
	for i in range(smooth_points.size() - 1):
		draw_line(smooth_points[i], smooth_points[i + 1], rope_color, rope_width)

func _draw_catenary_rope():
	"""Dessine une corde en simulant une chaînette (plus réaliste physiquement)"""
	var total_segments = 20
	
	for i in range(rope_points.size() - 1):
		var start = to_local(rope_points[i])
		var end = to_local(rope_points[i + 1])
		
		var points = _calculate_catenary(start, end, total_segments)
		
		for j in range(points.size() - 1):
			draw_line(points[j], points[j + 1], rope_color, rope_width)

func _calculate_catenary(start: Vector2, end: Vector2, segments: int) -> Array:
	"""Calcule les points d'une chaînette (forme naturelle d'une corde suspendue)"""
	var points = []
	var dx = end.x - start.x
	var dy = end.y - start.y
	
	# Paramètres de la chaînette
	var sag = max(abs(dx) * 0.1, 10.0)  # Affaissement de la corde
	
	# Si la corde est tendue verticalement, pas de chaînette
	if abs(dx) < 5.0:
		for i in range(segments + 1):
			var t = float(i) / float(segments)
			points.append(start.lerp(end, t))
		return points
	
	# Calcul de la chaînette
	var a = sag  # Paramètre de forme
	var x_offset = dx / 2.0
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var x = start.x + dx * t
		var local_x = (x - start.x - x_offset) / a
		
		# Formule de la chaînette: y = a * cosh(x/a)
		var cosh_val = (exp(local_x) + exp(-local_x)) / 2.0
		var catenary_y = a * (cosh_val - 1.0)
		
		# Ajuster pour que les extrémités correspondent
		var base_y = start.y + dy * t
		var y = base_y + catenary_y
		
		points.append(Vector2(x, y))
	
	return points

func _bezier_cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	"""Calcule un point sur une courbe de Bézier cubique"""
	var u = 1.0 - t
	var t2 = t * t
	var u2 = u * u
	var u3 = u2 * u
	var t3 = t2 * t
	
	return u3 * p0 + 3 * u2 * t * p1 + 3 * u * t2 * p2 + t3 * p3

func distance_point_to_line(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calcule la distance d'un point à une ligne"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	if line_vec.length_squared() == 0:
		return point_vec.length()
	
	var line_len = line_vec.length()
	var line_unitvec = line_vec / line_len
	var proj_length = clamp(point_vec.dot(line_unitvec), 0.0, line_len)
	var proj = line_start + line_unitvec * proj_length
	
	return point.distance_to(proj)

# Fonctions utilitaires
func move_anchor(new_position: Vector2):
	"""Déplace l'ancre vers une nouvelle position"""
	if anchor:
		anchor.global_position = new_position

func add_impulse_to_player(impulse: Vector2):
	"""Ajoute une impulsion au dernier point de la corde"""
	last_point_velocity += impulse

func get_player_velocity() -> Vector2:
	"""Retourne la vélocité actuelle du dernier point"""
	return last_point_velocity

func set_player_velocity(velocity: Vector2):
	"""Définit la vélocité du dernier point"""
	last_point_velocity = velocity

func get_rope_tension() -> float:
	"""Retourne la tension actuelle de la corde (0-1)"""
	var current_length = calculate_rope_length()
	return clamp(current_length / rope_length, 0.0, 1.0)
