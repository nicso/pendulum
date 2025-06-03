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
@export var rope_width: float = 3.0

# Paramètres de détection
@export var collision_margin: float = 5.0  # Augmenté pour plus de sécurité
@export var max_iterations: int = 50       
@export var corner_detection_distance: float = 10.0  # Distance pour détecter les coins

# Paramètres de gravité
@export var gravity: float = 980.0  # Pixels par seconde²
@export var damping: float = 0.98   # Amortissement pour stabiliser

# Variables pour la physique du dernier point de la corde
var last_point_velocity: Vector2 = Vector2.ZERO

# Stabilité temporelle pour éviter les oscillations
var point_removal_cooldown: Dictionary = {}  # Point index -> frames restantes
var cooldown_frames: int = 10  # Nombre de frames avant de pouvoir supprimer un point

# Obstacles 
var obstacles: Array[Node2D] = []

func _ready():
	# Initialiser avec deux points : ancre et joueur
	if anchor and player:
		rope_points = [anchor.global_position, player.global_position]
	
	# Récupérer tous les obstacles de la scène
	call_deferred("get_obstacles")

func _process(delta):
	if anchor and player and rope_points.size() >= 2:
		# Appliquer la gravité au dernier point de la corde
		apply_gravity_to_last_point(delta)
		
		# Mettre à jour la corde avec la physique
		update_rope_physics()
		
		# Vérifier et corriger les pénétrations
		fix_rope_penetrations()
		
		# Gérer les collisions du joueur avec la contrainte de la corde
		handle_player_physics_with_rope_constraint(delta)
		
		queue_redraw()

func handle_player_physics_with_rope_constraint(delta: float):
	"""Gère la physique du joueur en tenant compte des collisions ET de la contrainte de corde"""
	if not player:
		return
	
	# Position désirée selon la corde
	var rope_target_position = rope_points[rope_points.size() - 1]
	
	# Si le joueur est un CharacterBody2D, utiliser sa physique native
	if player is CharacterBody2D:
		handle_character_body_with_rope(player, rope_target_position, delta)
	else:
		# Pour les autres types de nœuds, utiliser un système de collision manuel
		handle_manual_collision_with_rope(rope_target_position, delta)

func handle_character_body_with_rope(character_body: CharacterBody2D, rope_target: Vector2, delta: float):
	"""Gère un CharacterBody2D avec contrainte de corde"""
	
	# Calculer le mouvement désiré selon la corde
	var desired_movement = rope_target - character_body.global_position
	
	# Limiter le mouvement selon la longueur de corde disponible
	var max_distance = rope_length * 0.99  # Petite marge
	var current_rope_length = calculate_rope_length_to_player()
	
	if current_rope_length + desired_movement.length() > max_distance:
		# Limiter le mouvement
		var available_distance = max_distance - current_rope_length
		if available_distance > 0:
			desired_movement = desired_movement.normalized() * min(desired_movement.length(), available_distance)
		else:
			desired_movement = Vector2.ZERO
	
	# Appliquer le mouvement avec les collisions natives
	character_body.velocity = desired_movement / delta
	character_body.move_and_slide()
	
	# Mettre à jour le dernier point de la corde avec la position réelle du joueur
	rope_points[rope_points.size() - 1] = character_body.global_position
	
	# Ajuster la vélocité de la corde selon le mouvement réel
	var actual_movement = character_body.global_position - (rope_target - desired_movement)
	last_point_velocity = actual_movement / delta

func handle_manual_collision_with_rope(rope_target: Vector2, delta: float):
	"""Gère les collisions manuellement pour les nœuds non-CharacterBody2D"""
	if not player:
		return
	
	var start_position = player.global_position
	var desired_position = rope_target
	
	# Vérifier s'il y a une collision sur le chemin
	var collision_info = check_player_collision(start_position, desired_position)
	
	if collision_info.has_collision:
		# Bouger jusqu'au point de collision
		player.global_position = collision_info.safe_position
		
		# Ajuster la vélocité (rebond ou glissement)
		var normal = collision_info.normal
		last_point_velocity = last_point_velocity - 2 * last_point_velocity.dot(normal) * normal
		last_point_velocity *= 0.8  # Perte d'énergie au contact
	else:
		# Mouvement libre
		player.global_position = desired_position
	
	# Mettre à jour le point de corde
	rope_points[rope_points.size() - 1] = player.global_position

func check_player_collision(start: Vector2, end: Vector2) -> Dictionary:
	"""Vérifie les collisions du joueur"""
	var result = {"has_collision": false, "safe_position": end, "normal": Vector2.ZERO}
	
	if not player:
		return result
	
	# Obtenir la forme de collision du joueur
	var collision_shape = null
	for child in player.get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return result
	
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return result
	
	# Créer une requête de mouvement avec la forme du joueur
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = Transform2D(0, end + collision_shape.position)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var collisions = space_state.intersect_shape(query)
	
	if collisions.size() > 0:
		# Il y a collision, trouver une position sûre
		result.has_collision = true
		
		# Utiliser un raycast pour trouver le point de contact
		var ray_query = PhysicsRayQueryParameters2D.create(start, end)
		ray_query.collision_mask = 1
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		
		var ray_result = space_state.intersect_ray(ray_query)
		
		if not ray_result.is_empty():
			result.normal = ray_result.normal
			# Position sûre avec une petite marge
			result.safe_position = ray_result.position - (end - start).normalized() * 5.0
		else:
			result.safe_position = start
	
	return result

func calculate_rope_length_to_player() -> float:
	"""Calcule la longueur de corde jusqu'à l'avant-dernier point (sans compter le segment final vers le joueur)"""
	if rope_points.size() < 2:
		return 0.0
	
	var length = 0.0
	for i in range(rope_points.size() - 2):
		length += rope_points[i].distance_to(rope_points[i + 1])
	
	return length

func get_obstacles():
	"""Récupère tous les obstacles de la scène"""
	obstacles.clear()
	var obstacle_nodes = get_tree().get_nodes_in_group("obstacle")
	for node in obstacle_nodes:
		if node is StaticBody2D or node is CharacterBody2D:
			obstacles.append(node)

func apply_gravity_to_last_point(delta: float):
	"""Applique la gravité uniquement au dernier point de la corde"""
	# Appliquer la gravité à la vélocité du dernier point
	last_point_velocity.y += gravity * delta
	
	# Appliquer l'amortissement pour éviter les oscillations
	last_point_velocity *= damping
	
	# Calculer la nouvelle position du dernier point
	var desired_last_position = rope_points[rope_points.size() - 1] + last_point_velocity * delta
	
	# Mettre à jour le dernier point
	rope_points[rope_points.size() - 1] = desired_last_position

func update_rope_physics():
	"""Met à jour la physique de la corde"""
	if not anchor:
		return
	
	# Toujours mettre à jour la position de l'ancre
	rope_points[0] = anchor.global_position
	
	# Vérifier et nettoyer les segments qui ne sont plus bloqués
	clean_unnecessary_points()
	
	# Ajouter de nouveaux points de collision si nécessaire
	add_missing_collision_points()
	
	# Contraindre la corde selon sa longueur maximale
	constrain_rope_length()

func fix_rope_penetrations():
	"""Corrige les pénétrations de la corde dans les obstacles"""
	var max_fixes = 10  # Éviter les boucles infinies
	var fixes_applied = 0
	
	while fixes_applied < max_fixes:
		var penetration_fixed = false
		
		# Vérifier chaque segment de la corde
		for i in range(rope_points.size() - 1):
			var start_point = rope_points[i]
			var end_point = rope_points[i + 1]
			
			# Vérifier si ce segment traverse un obstacle
			var collision_info = get_detailed_collision_info(start_point, end_point)
			
			if collision_info.has_collision:
				# Trouver le meilleur point de contournement
				var bypass_point = find_best_bypass_point(start_point, end_point, collision_info)
				
				if bypass_point != Vector2.ZERO:
					# Insérer le point de contournement
					rope_points.insert(i + 1, bypass_point)
					penetration_fixed = true
					break
		
		if not penetration_fixed:
			break
		
		fixes_applied += 1

func get_detailed_collision_info(start: Vector2, end: Vector2) -> Dictionary:
	"""Obtient des informations détaillées sur la collision"""
	var result = {"has_collision": false, "collision_point": Vector2.ZERO, "normal": Vector2.ZERO, "collider": null}
	
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return result
	
	var query = PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var collision = space_state.intersect_ray(query)
	
	if not collision.is_empty() and collision.has("collider"):
		result.has_collision = true
		result.collision_point = collision.position
		result.normal = collision.normal
		result.collider = collision.collider
	
	return result

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
		# Choisir le coin le plus proche qui permet un passage libre
		var best_corner = Vector2.ZERO
		var best_distance = INF
		
		for corner in corner_points:
			# Vérifier si on peut aller du point de départ au coin
			if not segment_has_collision(start, corner):
				# Vérifier si on peut aller du coin au point d'arrivée
				if not segment_has_collision(corner, end):
					var distance = start.distance_to(corner) + corner.distance_to(end)
					if distance < best_distance:
						best_distance = distance
						best_corner = corner
		
		if best_corner != Vector2.ZERO:
			return best_corner
	
	# Si pas de coin trouvé, utiliser la normale avec une marge plus grande
	var bypass_point = collision_point + normal * (collision_margin * 2)
	
	# Vérifier que ce point ne cause pas de nouvelle collision
	if not segment_has_collision(start, bypass_point) and not segment_has_collision(bypass_point, end):
		return bypass_point
	
	return Vector2.ZERO

func find_obstacle_corners(collider: Node2D) -> Array[Vector2]:
	"""Trouve les coins d'un obstacle"""
	var corners: Array[Vector2] = []
	
	if not is_instance_valid(collider):
		return corners
	
	# Essayer d'obtenir la forme de collision
	var collision_shape = null
	for child in collider.get_children():
		if child is CollisionShape2D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return corners
	
	var shape = collision_shape.shape
	var transform = collider.global_transform * collision_shape.transform
	
	if shape is RectangleShape2D:
		var size = shape.size
		var half_size = size * 0.5
		
		# Les 4 coins du rectangle
		corners.append(transform * Vector2(-half_size.x, -half_size.y))
		corners.append(transform * Vector2(half_size.x, -half_size.y))
		corners.append(transform * Vector2(half_size.x, half_size.y))
		corners.append(transform * Vector2(-half_size.x, half_size.y))
		
		# Ajouter une marge aux coins
		for i in range(corners.size()):
			var center = transform.origin
			var direction = (corners[i] - center).normalized()
			corners[i] += direction * collision_margin
	
	return corners

func constrain_rope_length():
	"""Contraint la corde selon sa longueur maximale"""
	var total_length = calculate_rope_length()
	
	if total_length > rope_length:
		# La corde est trop tendue, contraindre
		var old_last_point = rope_points[rope_points.size() - 1]
		rope_points = limit_rope_length(rope_points, rope_length)
		var new_last_point = rope_points[rope_points.size() - 1]
		
		# Calculer la nouvelle vélocité basée sur la contrainte
		if rope_points.size() >= 2:
			var rope_direction = (rope_points[rope_points.size() - 1] - rope_points[rope_points.size() - 2]).normalized()
			var tangent = Vector2(-rope_direction.y, rope_direction.x)  # Perpendiculaire à la corde
			
			# Projeter la vélocité sur la direction tangente à la corde
			last_point_velocity = tangent * last_point_velocity.dot(tangent)
			
			# Ajouter un petit effet de rebond si la corde se tend brusquement
			var constraint_force = (new_last_point - old_last_point).length()
			if constraint_force > 0:
				var bounce_direction = (new_last_point - old_last_point).normalized()
				last_point_velocity += bounce_direction * constraint_force * 0.1

func clean_unnecessary_points():
	"""Supprime les points de pliage qui ne sont plus nécessaires avec stabilité"""
	# Décrémenter les cooldowns
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
		
		# Vérifier le cooldown pour ce point
		if point_removal_cooldown.has(i):
			i += 1
			continue
		
		# Vérifier si on peut connecter directement prev_point à next_point
		var can_connect_directly = not segment_has_collision(prev_point, next_point)
		
		if can_connect_directly:
			# Vérifications supplémentaires pour éviter les "sauts" illogiques
			var direct_distance = prev_point.distance_to(next_point)
			var current_path_distance = prev_point.distance_to(current_point) + current_point.distance_to(next_point)
			
			# Ne supprimer que si :
			# 1. Le chemin direct n'est pas beaucoup plus court (évite les sauts)
			# 2. ET le point actuel n'est pas trop éloigné de la ligne directe
			var distance_ratio = direct_distance / current_path_distance
			var line_to_point_distance = distance_point_to_line(current_point, prev_point, next_point)
			
			# Seuils pour la stabilité
			var max_distance_reduction = 0.85  # Ne pas réduire de plus de 15% la distance
			var max_deviation = 20.0  # Distance maximale du point à la ligne directe
			
			if distance_ratio > max_distance_reduction and line_to_point_distance < max_deviation:
				rope_points.remove_at(i)
				
				# Ajouter un cooldown pour les points suivants (décalage d'index)
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
			# Insérer le nouveau point de collision
			rope_points.insert(i + 1, collision_result.contact_point)
			
			# Ajouter un cooldown pour ce nouveau point pour éviter qu'il soit immédiatement supprimé
			point_removal_cooldown[i + 1] = cooldown_frames
			
			# Ajuster les index des cooldowns existants
			var new_cooldowns = {}
			for key in point_removal_cooldown.keys():
				if key > i + 1:
					new_cooldowns[key + 1] = point_removal_cooldown[key]
				else:
					new_cooldowns[key] = point_removal_cooldown[key]
			point_removal_cooldown = new_cooldowns
			
			# Passer au segment suivant (on skip le point qu'on vient d'ajouter)
			i += 2
		else:
			i += 1

func segment_has_collision(start: Vector2, end: Vector2) -> bool:
	"""Vérifie rapidement si un segment a une collision"""
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return false
	
	var query = PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var collision = space_state.intersect_ray(query)
	return not collision.is_empty()

func find_collision_on_segment(start: Vector2, end: Vector2) -> Dictionary:
	"""Trouve une collision sur un segment spécifique"""
	var result = {"has_collision": false, "contact_point": Vector2.ZERO}
	
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return result
	
	var query = PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var collision = space_state.intersect_ray(query)
	
	if collision.is_empty() or not collision.has("collider"):
		return result
	
	var collider = collision.collider
	if not is_instance_valid(collider):
		return result
	
	var collision_point = collision.position
	var normal = collision.normal
	
	# Calculer le point de contact avec une marge
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
	
	var new_points: Array[Vector2] = [points[0]]  # Commencer par l'ancre
	var current_length = 0.0
	
	for i in range(1, points.size()):
		var segment_length = new_points[new_points.size() - 1].distance_to(points[i])
		
		if current_length + segment_length <= max_length:
			# Le segment entier peut être ajouté
			new_points.append(points[i])
			current_length += segment_length
		else:
			# Ajouter seulement une partie du segment
			var remaining_length = max_length - current_length
			if remaining_length > 0:
				var direction = (points[i] - new_points[new_points.size() - 1]).normalized()
				var final_point = new_points[new_points.size() - 1] + direction * remaining_length
				new_points.append(final_point)
			break
	
	return new_points

func _draw():
	"""Dessine la corde"""
	if rope_points.size() < 2:
		return
	
	# Dessiner les segments de corde
	for i in range(rope_points.size() - 1):
		var start = to_local(rope_points[i])
		var end = to_local(rope_points[i + 1])
		draw_line(start, end, rope_color, rope_width)
	
	# Dessiner les points de pliage
	for i in range(1, rope_points.size() - 1):
		var point = to_local(rope_points[i])
		draw_circle(point, 4, Color.RED)
	
	# Dessiner l'ancre et le joueur
	if rope_points.size() > 0:
		draw_circle(to_local(rope_points[0]), 6, Color.GREEN)  # Ancre
		draw_circle(to_local(rope_points[rope_points.size() - 1]), 6, Color.BLUE)  # Joueur

func distance_point_to_line(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calcule la distance d'un point à une ligne"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	if line_vec.length_squared() == 0:
		return point_vec.length()
	
	var line_len = line_vec.length()
	var line_unitvec = line_vec / line_len
	
	var proj_length = point_vec.dot(line_unitvec)
	proj_length = clamp(proj_length, 0.0, line_len)
	
	var proj = line_start + line_unitvec * proj_length
	return point.distance_to(proj)

# Fonctions utilitaires
func move_anchor(new_position: Vector2):
	"""Déplace l'ancre vers une nouvelle position"""
	if anchor:
		anchor.global_position = new_position

func add_impulse_to_player(impulse: Vector2):
	"""Ajoute une impulsion au dernier point de la corde (pour les contrôles)"""
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
