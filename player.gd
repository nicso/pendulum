extends CharacterBody2D
class_name Player

@onready var weapon_point = $WeaponPoint  # Point d'où sortent les projectiles
@onready var rope_system: RopeSystem = %RopeSystem

# Paramètres de tir
var fire_rate = 0.2
var can_shoot = true
var bullet_speed = 1800
var bullet_damage = 25
var weapon_recoil = 400

# Visée
var aim_direction = Vector2.RIGHT
var last_move_direction = Vector2.RIGHT

# Paramètres pour la rotation du weapon_point
@export var weapon_distance = 200.0  # Distance du weapon_point par rapport au centre du joueur
@export var rotation_speed = 10.0   # Vitesse de rotation (plus c'est élevé, plus c'est rapide)

func _ready():
	# Position initiale du weapon_point
	weapon_point.position = Vector2(weapon_distance, 0)

func _physics_process(delta):
	handle_aiming()
	handle_shooting()
	update_weapon_point_position(delta)

func handle_aiming():
	# Visée à la souris (prioritaire)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var mouse_pos = get_global_mouse_position()
		if global_position.distance_to(mouse_pos) > 20:  # Zone morte
			aim_direction = (mouse_pos - global_position).normalized()
	
	# Visée au stick droit (manette)
	var aim_x = Input.get_axis("aim_left", "aim_right")
	var aim_y = Input.get_axis("aim_up", "aim_down")
	
	if abs(aim_x) > 0.3 or abs(aim_y) > 0.3:  # Zone morte du stick
		aim_direction = Vector2(aim_x, aim_y).normalized()
	elif aim_direction == Vector2.ZERO:
		# Si pas de visée active, vise dans la direction du mouvement
		aim_direction = last_move_direction

func update_weapon_point_position(delta):
	# Calcule la position cible du weapon_point
	var target_position = aim_direction * weapon_distance
	
	# Rotation fluide vers la position cible
	weapon_point.position = weapon_point.position.move_toward(target_position, rotation_speed * weapon_distance * delta)
	
	# Alternative : rotation instantanée (décommente si tu préfères)
	# weapon_point.position = target_position

func handle_shooting():
	var wants_to_shoot = false
	
	# Tir à la souris
	if Input.is_action_pressed("shoot_mouse"):
		wants_to_shoot = true
	
	# Tir à la manette
	if Input.is_action_pressed("shoot_gamepad"):
		wants_to_shoot = true
	
	if wants_to_shoot and can_shoot:
		shoot()

func shoot():
	if aim_direction == Vector2.ZERO:
		aim_direction = last_move_direction
	
	# Position de spawn du projectile
	var spawn_pos = weapon_point.global_position
	
	# Spawn du projectile
	BulletManager.spawn_bullet(spawn_pos, aim_direction, bullet_speed, bullet_damage)
	rope_system.add_impulse_to_player(-aim_direction * weapon_recoil )
	# Cooldown de tir
	can_shoot = false
	get_tree().create_timer(fire_rate).timeout.connect(func(): can_shoot = true)

func take_damage(amount: int):
	print("Player took ", amount, " damage!")
	# Implémente ici la logique de dégâts du joueur
