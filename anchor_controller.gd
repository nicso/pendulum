# RopeController.gd
extends Node

@export var anchor_speed: float = 500.0
@export var player_impulse_force: float = 40.0  # Force pour faire bouger le joueur
@export var rope_system: RopeSystem

func _ready():
	# S'assurer que le rope_system est configuré
	if not rope_system:
		rope_system = get_node("RopeSystem")

func _process(delta):
	handle_input(delta)

func handle_input(delta):
	"""Gère les entrées pour déplacer l'ancre et contrôler le joueur"""
	# Contrôle de l'ancre
	var anchor_input = Vector2.ZERO
	
	if Input.is_action_pressed("ui_left"):
		anchor_input.x -= 1
	if Input.is_action_pressed("ui_right"):
		anchor_input.x += 1
	if Input.is_action_pressed("ui_up"):
		anchor_input.y -= 1
	if Input.is_action_pressed("ui_down"):
		anchor_input.y += 1
	
	if anchor_input != Vector2.ZERO:
		var new_position = rope_system.anchor.global_position + anchor_input * anchor_speed * delta
		rope_system.move_anchor(new_position)
	
	# Contrôle du joueur (impulsions)
	if Input.is_action_just_pressed("ui_accept"):  # Espace pour donner une impulsion vers le haut
		rope_system.add_impulse_to_player(Vector2(0, -player_impulse_force))
	
	# Impulsions latérales pour faire balancer le joueur
	if Input.is_action_pressed("game_move_left"):  # A ou flèche gauche
		rope_system.add_impulse_to_player(Vector2(-player_impulse_force * 0.5, 0))
	if Input.is_action_pressed("game_move_right"):  # D ou flèche droite
		rope_system.add_impulse_to_player(Vector2(player_impulse_force * 0.5, 0))
