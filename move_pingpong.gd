@tool
extends Node2D

# Array de positions relatives par rapport à la position initiale
@export var relative_positions: Array[Vector2] = [
	Vector2(0, 0),      # Position de départ
	Vector2(200, 0),    # Droite
	Vector2(200, 200),  # Bas-droite
	Vector2(0, 200),    # Bas
	Vector2(-200, 200), # Bas-gauche
	Vector2(-200, 0),   # Gauche
	Vector2(-200, -200),# Haut-gauche
	Vector2(0, -200)    # Haut
]: set = set_relative_positions

# Durée du mouvement entre chaque point
@export var duration: float = 1.0

# Type d'easing
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var transition_type: Tween.TransitionType = Tween.TRANS_SINE

# Comportement de la boucle
@export var loop_mode: LoopMode = LoopMode.REPEAT
enum LoopMode {
	REPEAT,     # Revient au début après le dernier point
	PING_PONG   # Va-et-vient (inverse l'ordre)
}

# Paramètres de prévisualisation
@export_group("Prévisualisation")
@export var show_preview: bool = true: set = set_show_preview
@export var line_color: Color = Color.CYAN: set = set_line_color
@export var line_width: float = 2.0: set = set_line_width
@export var point_color: Color = Color.RED: set = set_point_color
@export var point_radius: float = 5.0: set = set_point_radius
@export var show_numbers: bool = true: set = set_show_numbers

# Variables internes
var tween: Tween
var current_index: int = 0
var initial_position: Vector2
var going_forward: bool = true

func _ready():
	# Sauvegarder la position initiale
	initial_position = position
	
	# Ne démarrer le mouvement qu'en jeu (pas dans l'éditeur)
	if not Engine.is_editor_hint():
		# Vérifier qu'on a au moins 2 positions
		if relative_positions.size() < 2:
			push_warning("Il faut au moins 2 positions pour le mouvement")
			return
		
		# Démarrer le mouvement
		start_movement()

func _draw():
	if not show_preview or relative_positions.size() < 2:
		return
	
	# Dessiner les lignes du chemin
	for i in range(relative_positions.size()):
		var current_pos = relative_positions[i]
		var next_pos: Vector2
		
		# Déterminer la prochaine position selon le mode de boucle
		if loop_mode == LoopMode.REPEAT:
			next_pos = relative_positions[(i + 1) % relative_positions.size()]
		else: # PING_PONG
			if i == relative_positions.size() - 1:
				if relative_positions.size() > 2:
					next_pos = relative_positions[i - 1]
				else:
					next_pos = relative_positions[0]
			else:
				next_pos = relative_positions[i + 1]
		
		# Dessiner la ligne
		draw_line(current_pos, next_pos, line_color, line_width)
	
	# Dessiner les points
	for i in range(relative_positions.size()):
		var pos = relative_positions[i]
		draw_circle(pos, point_radius, point_color)
		
		# Dessiner les numéros
		if show_numbers:
			var font = ThemeDB.fallback_font
			var font_size = 12
			var text = str(i)
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var text_pos = pos - text_size * 0.5
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

# Setters pour mettre à jour la prévisualisation
func set_relative_positions(value: Array[Vector2]):
	relative_positions = value
	queue_redraw()

func set_show_preview(value: bool):
	show_preview = value
	queue_redraw()

func set_line_color(value: Color):
	line_color = value
	queue_redraw()

func set_line_width(value: float):
	line_width = value
	queue_redraw()

func set_point_color(value: Color):
	point_color = value
	queue_redraw()

func set_point_radius(value: float):
	point_radius = value
	queue_redraw()

func set_show_numbers(value: bool):
	show_numbers = value
	queue_redraw()

func start_movement():
	if relative_positions.is_empty() or Engine.is_editor_hint():
		return
	
	# Calculer la position absolue de destination
	var target_relative = relative_positions[current_index]
	var target_absolute = initial_position + target_relative
	
	# Créer et configurer le Tween
	tween = create_tween()
	tween.set_ease(ease_type)
	tween.set_trans(transition_type)
	
	# Animer vers la position cible
	tween.tween_property(self, "position", target_absolute, duration)
	tween.tween_callback(on_tween_finished)

func on_tween_finished():
	if Engine.is_editor_hint():
		return
	
	# Calculer le prochain index selon le mode de boucle
	match loop_mode:
		LoopMode.REPEAT:
			current_index = (current_index + 1) % relative_positions.size()
		
		LoopMode.PING_PONG:
			if going_forward:
				current_index += 1
				if current_index >= relative_positions.size() - 1:
					going_forward = false
			else:
				current_index -= 1
				if current_index <= 0:
					going_forward = true
	
	# Continuer le mouvement
	start_movement()

# Fonction pour changer les positions en cours de route
func set_relative_positions_runtime(new_positions: Array[Vector2]):
	relative_positions = new_positions
	if not Engine.is_editor_hint():
		restart_movement()

# Fonction pour arrêter le mouvement
func stop_movement():
	if tween:
		tween.kill()

# Fonction pour redémarrer le mouvement depuis le début
func restart_movement():
	if Engine.is_editor_hint():
		return
	
	stop_movement()
	current_index = 0
	going_forward = true
	position = initial_position
	start_movement()

# Fonction pour aller directement à un point spécifique
func go_to_point(index: int):
	if Engine.is_editor_hint():
		return
	
	if index >= 0 and index < relative_positions.size():
		stop_movement()
		current_index = index
		start_movement()

# Fonction pour définir une nouvelle position initiale
func set_initial_position(new_pos: Vector2):
	initial_position = new_pos
	if not Engine.is_editor_hint():
		restart_movement()
