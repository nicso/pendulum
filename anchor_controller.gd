# RopeController.gd
extends Node

@export var anchor_speed: float = 50.0
@export var player_impulse_force: float = 40.0  # Force pour faire bouger le joueur
@export var min_rope_lenght := 400.0
@export var max_rope_lenght := 1800.0
@export var rope_system: RopeSystem

@onready var player: Player = $"../Player"
var new_position := Vector2.ZERO
func _ready():
	
	# S'assurer que le rope_system est configuré
	if not rope_system:
		rope_system = get_node("RopeSystem")
	new_position = rope_system.anchor.global_position
	
func _process(delta):
	handle_input(delta)

func handle_input(delta):
	"""Gère les entrées pour déplacer l'ancre et contrôler le joueur"""
	# Contrôle de l'ancre
	var anchor_input = Vector2.ZERO
	
	if Input.is_action_pressed("game_move_left"):
		anchor_input.x -= 1
	if Input.is_action_pressed("game_move_right"):
		anchor_input.x += 1
	
	if Input.is_action_pressed("game_move_up") and not player.is_on_ceiling() and rope_system.rope_length > min_rope_lenght:
		rope_system.rope_length -= 400 * delta
	if Input.is_action_pressed("game_move_down") and not player.is_on_floor() and rope_system.rope_length < max_rope_lenght:
		rope_system.rope_length += 400 * delta
	
	if anchor_input != Vector2.ZERO:
		new_position = rope_system.anchor.global_position + anchor_input * anchor_speed 
		
	rope_system.move_anchor(rope_system.anchor.global_position.lerp(new_position, 6.0 * delta))


		
