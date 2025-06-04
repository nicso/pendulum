extends Area2D

@onready var sprite = $Sprite2D
@onready var collision = $CollisionShape2D

var speed = 5800
var direction = Vector2.ZERO
var damage = 10
var lifetime = 5.0
var timer = 0.0

signal hit_target(target, damage)

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _process(delta):
	if not visible:
		return
		
	# Déplacement
	position += direction * speed * delta
	
	# Gestion du temps de vie
	timer += delta
	if timer >= lifetime:
		BulletManager.return_bullet(self)
		return
	
	# Culling hors écran (avec marge)

	var camera_rect = get_canvas_transform().affine_inverse() * get_viewport_rect()
	camera_rect = camera_rect.grow(1000) 
	if not camera_rect.has_point(global_position):
		BulletManager.return_bullet(self)

func initialize(pos: Vector2, dir: Vector2, bullet_speed: float = 800, bullet_damage: int = 10):
	global_position = pos
	direction = dir.normalized()
	speed = bullet_speed
	damage = bullet_damage
	timer = 0.0
	
	# Rotation du sprite selon la direction
	rotation = direction.angle()
	
	# Activation
	visible = true
	set_process(true)
	collision.disabled = false

func deactivate():
	visible = false
	set_process(false)
	collision.disabled = true
	timer = 0.0

func _on_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(damage)
		hit_target.emit(body, damage)
	BulletManager.return_bullet(self)

func _on_area_entered(area):
	# Collision avec d'autres zones (power-ups, obstacles, etc.)
	if area.has_method("on_bullet_hit"):
		area.on_bullet_hit(self)
	BulletManager.return_bullet(self)
